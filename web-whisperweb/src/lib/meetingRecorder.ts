import type { MeetingStageSnapshot } from "./meetingStageCapture";
import workletURL from "./recordingPCM.worklet.js?url";
import { MeetPipMosaic, type PipMosaicSource } from "./meetPipMosaic";
import { pcmWav, type MeetingRecording } from "./meetingRecordingModel";
import { createRecording, editRecording, saveRecordingChunk, loadRecordingChunk } from "./meetingRecordingStorage";
import { verifyStoredRecording } from "./verifyStoredRecording";
import { attachFinalizedRecordingNote } from "./recordingNotebook";
import { RecordingSpeakerCapture } from './recordingSpeakerCapture';
import { MeetingTranscriptionError } from './meetingTranscription';
import { transcribeRecordingChunk } from "./recordingTranscription";

export type RecorderUpdate = { state: "starting" | "recording" | "saving" | "ready" | "error"; seconds: number; error: string | null; recordingId: string; audioInputs: number; transcriptionPending?: boolean };
/** Owns only recording resources. Never stops, clones or publishes the call's tracks. */
export class MeetingRecorder {
  readonly id = crypto.randomUUID();
  stageSnapshot: (() => MeetingStageSnapshot | null) | undefined;
  private context: AudioContext | null = null;
  private mix: GainNode | null = null;
  private destination: MediaStreamAudioDestinationNode | null = null;
  private pcm: AudioWorkletNode | null = null;
  private mosaic: MeetPipMosaic | null = null;
  private recorder: MediaRecorder | null = null;
  private inputs = new Map<MediaStreamTrack, MediaStreamAudioSourceNode>();
  private startedAt = 0;
  private wallStart = 0;
  private createdAt = '';
  private finalSeconds: number | null = null;
  private captureFailed = false;
  private captureStarted = false;
  private stopping = false;
  private mediaIndex = 0;
  private audioIndex = 0;
  private bytes = 0;
  private timer: ReturnType<typeof setInterval> | null = null;
  private writes: Promise<void> = Promise.resolve();
  private transcription: Promise<void> = Promise.resolve();
  private cloudFinalization: Promise<void> | null = null;
  private pendingTranscription = 0;
  private speakerCapture: RecordingSpeakerCapture | null = null;
  private speakerIndex = 0;
  private transcriptionFailed = false;
  private transcribeEnabled = true;
  private readonly cloud = new AbortController();
  private readonly startupAbort = new AbortController();
  private stopPromise: Promise<void> | null = null;
  private stoppedPCM: (() => void) | null = null;
  private state: RecorderUpdate["state"] = "starting";
  private error: string | null = null;
  private reserved = false;
  private startPromise: Promise<void> | null = null;
  private latestSources: PipMosaicSource[] = [];
  private acceptingChunks = true;
  constructor(readonly ownerId: string, readonly meetingId: string | null, private title: string, private readonly onUpdate: (value: RecorderUpdate) => void, preparedAudio: AudioContext | null = null) { this.context = preparedAudio; }
  get seconds(): number { return this.finalSeconds ?? (this.captureStarted && this.context ? Math.max(0, this.context.currentTime - this.startedAt) : 0); }
  get cloudCompletion(): Promise<void> { return this.writes.then(() => this.cloudFinalization ?? this.transcription); }
  private emit(): void { try { this.onUpdate({ state: this.state, seconds: this.seconds, error: this.error, recordingId: this.id, audioInputs: this.inputs.size, transcriptionPending: this.pendingTranscription > 0 }); } catch { /* UI observers never own capture or storage cleanup. */ } }
  private async startup(work: Promise<void>): Promise<void> {
    const signal = this.startupAbort.signal;
    await new Promise<void>((resolve, reject) => {
      const cancel = (): void => { clearTimeout(timer); reject(new Error("Recording start was cancelled.")); };
      const timer = setTimeout(() => { signal.removeEventListener("abort", cancel); reject(new Error("Audio setup took too long. Restore audio and try again.")); }, 30000);
      signal.addEventListener("abort", cancel, { once: true });
      work.then(resolve, reject).finally(() => { clearTimeout(timer); signal.removeEventListener("abort", cancel); });
      if (signal.aborted) cancel();
    });
  }
  private disconnectInputs(): void {
    for (const node of this.inputs.values()) { try { node.disconnect(); } catch { this.captureFailed = true; } }
    this.inputs.clear();
  }
  start(sources: PipMosaicSource[], video: boolean, transcribe: boolean, archive = false): Promise<void> {
    if (this.startPromise) return this.startPromise;
    this.latestSources = sources;
    this.startPromise = this.begin(video, transcribe, archive); return this.startPromise;
  }
  private async begin(video: boolean, transcribe: boolean, archive: boolean): Promise<void> {
    this.transcribeEnabled = transcribe;
    try {
      if (this.stopping) throw new Error("Recording start was cancelled.");
      if (typeof MediaRecorder === "undefined" || typeof AudioWorkletNode === "undefined") throw new Error("Recording needs a recent browser with audio recording support.");
      this.context ??= new AudioContext({ sampleRate: 24000 });
      const context = this.context;
      await this.startup(context.resume());
      if (this.stopping) throw new Error("Recording start was cancelled.");
      await this.startup(context.audioWorklet.addModule(workletURL));
      if (this.stopping) throw new Error("Recording start was cancelled.");
      this.mix = this.context.createGain();
      const limiter = this.context.createDynamicsCompressor();
      limiter.threshold.value = -3; limiter.knee.value = 0; limiter.ratio.value = 20;
      this.mix.connect(limiter);
      this.destination = this.context.createMediaStreamDestination(); limiter.connect(this.destination);
      this.pcm = new AudioWorkletNode(this.context, "whisper-recording-pcm", { channelCount: 1 }); limiter.connect(this.pcm);
      const silent = this.context.createGain(); silent.gain.value = 0; this.pcm.connect(silent); silent.connect(this.context.destination);
      this.update(this.latestSources);
      if (!this.inputs.size) throw new Error("No meeting audio has arrived yet. Wait for audio or turn on your microphone, then try again.");
      let stream = this.destination.stream;
      if (video) { this.mosaic = new MeetPipMosaic(1280, 720, true); this.mosaic.stageSnapshot = this.stageSnapshot; this.mosaic.update(this.latestSources); this.mosaic.start(); stream = new MediaStream([...this.destination.stream.getAudioTracks(), ...this.mosaic.mediaStream.getVideoTracks()]); }
      const candidates = video ? ["video/mp4;codecs=avc1.42E01E,mp4a.40.2", "video/webm;codecs=vp8,opus", "video/webm"] : ["audio/mp4", "audio/webm;codecs=opus", "audio/webm"];
      const mimeType = candidates.find((candidate) => MediaRecorder.isTypeSupported(candidate));
      if (!mimeType) throw new Error("This browser cannot encode this recording. Try a recent Chrome or Safari browser.");
      this.recorder = new MediaRecorder(stream, { mimeType, videoBitsPerSecond: 1_200_000, audioBitsPerSecond: 64000 });
      const record: MeetingRecording = { version: 1, id: this.id, ownerId: this.ownerId, meetingId: this.meetingId, title: this.title.slice(0, 160), createdAt: new Date().toISOString(), lastWriteAt: Date.now(), duration: 0, mimeType: this.recorder.mimeType, status: "recording", storageConsent: archive, cloudConsent: transcribe, speakerTranscription: transcribe, transcriptionState: transcribe ? 'pending' : 'off', coverage: video ? "Meeting voices received by this browser plus your outgoing audio; up to 25 video tiles and shared screen. No shared-screen sound, chat, or private Jasper panels. Keep this browser awake and visible." : "Meeting voices received by this browser plus your outgoing audio. No other-app or shared-screen sound. Keep this browser awake.", transcript: [], markers: [], warnings: [], revision: 0 };
      this.createdAt = record.createdAt;
      await createRecording(record); this.reserved = true;
      if (this.stopping) throw new Error("Recording start was cancelled.");
      this.recorder.ondataavailable = (event: BlobEvent) => {
        if (!event.data.size || !this.acceptingChunks) return;
        this.bytes += event.data.size; const index = this.mediaIndex++; const end = this.seconds;
        this.writes = this.writes.then(async () => { await saveRecordingChunk(this.ownerId, this.id, { kind: "media", index, start: 0, end, blob: event.data, transcribed: false }); }).catch(() => this.storageFailure());
        if (this.bytes > 450 * 1024 * 1024) { this.error = "Recording stopped at the 450 MB limit. Start a new recording to continue."; void this.stop(); }
      };
      this.recorder.onerror = () => { this.captureFailed = true; this.error = "The browser interrupted recording. Saved parts are retained."; void this.stop(); };
      this.pcm.port.onmessage = (event: MessageEvent<{ stopped?: boolean; samples?: Float32Array; rate: number; start: number; end: number }>) => {
        if (event.data.stopped) { this.stoppedPCM?.(); return; }
        const { samples, rate, start, end } = event.data;
        if (!samples?.length || !this.acceptingChunks) return;
        const index = this.audioIndex++; const blob = pcmWav(samples, rate);
        this.bytes += blob.size;
        if (this.bytes > 450 * 1024 * 1024 && !this.stopPromise) { this.error = "Recording stopped at the 450 MB storage limit. Start a new recording to continue."; void this.stop(); }
        const relativeStart = Math.max(0, start - this.startedAt); const relativeEnd = Math.max(relativeStart, end - this.startedAt);
        this.writes = this.writes.then(async () => {
          const chunk = await saveRecordingChunk(this.ownerId, this.id, { kind: "audio", index, start: relativeStart, end: relativeEnd, blob, transcribed: false });
          // The mixed WAV remains the playback backup. Named transcript uses isolated sources.
          void chunk;
        }).catch(() => this.storageFailure());
      };
      this.update(this.latestSources);
      this.startedAt = this.context.currentTime; this.wallStart = performance.now();
      this.recorder.start(3000); this.captureStarted = true; this.pcm.port.postMessage("start");
      if (transcribe) {
        this.speakerCapture = new RecordingSpeakerCapture(this.context, this.startedAt, (value) => {
          if (!this.acceptingChunks) return;
          const index = this.speakerIndex++; this.bytes += value.blob.size;
          if (this.bytes > 450 * 1024 * 1024 && !this.stopPromise) void this.stop();
          this.writes = this.writes.then(async () => {
            const chunk = await saveRecordingChunk(this.ownerId, this.id, { ...value, kind: 'speaker', index, transcribed: false });
            if (this.cloud.signal.aborted) return;
            this.queueSpeech(chunk.key);
          }).catch(() => this.storageFailure());
        });
        this.speakerCapture.update(this.latestSources);
      }
      this.state = "recording"; this.emit();
      this.context.onstatechange = () => { if (this.state === "recording" && this.context?.state !== "running") { this.captureFailed = true; this.error = "Audio capture was interrupted. Start a new recording after restoring audio."; void this.stop(); } };
      this.timer = setInterval(() => { this.emit(); if ((performance.now() - this.wallStart) / 1000 >= 7200) { this.error = "Two-hour recording limit reached. Start another recording to continue."; void this.stop(); } }, 1000);
    } catch (error) {
      this.captureFailed = true;
      this.error = error instanceof Error ? error.message : "Recording could not start.";
      if (!this.stopping) {
        this.state = "error"; this.release(); this.emit();
        if (this.reserved) await editRecording(this.ownerId, this.id, (record) => ({ ...record, status: "interrupted", warnings: [this.error ?? "Recording did not start."] }));
      }
      throw error;
    }
  }
  /** Roster reconciliation includes camera-off and off-grid participants' audio exactly once. */
  update(sources: PipMosaicSource[]): void {
    this.latestSources = sources;
    if (!this.context || !this.mix || this.stopping) return;
    const tracks = new Set(sources.flatMap((source) => source.stream?.getAudioTracks().filter((track) => track.readyState === "live") ?? []));
    for (const [track, node] of this.inputs) if (!tracks.has(track)) { node.disconnect(); this.inputs.delete(track); }
    for (const track of tracks) if (!this.inputs.has(track)) { const node = this.context.createMediaStreamSource(new MediaStream([track])); node.connect(this.mix); this.inputs.set(track, node); }
    this.mosaic?.update(sources);
    this.speakerCapture?.update(sources);
  }
  private queueSpeech(key: string): void {
    if (this.pendingTranscription >= 20000) { this.transcriptionFailed = true; return; }
    this.pendingTranscription++;
    this.transcription = this.transcription.then(async () => {
      this.cloud.signal.throwIfAborted();
      const chunk = await loadRecordingChunk(key);
      for (let attempt = 0; attempt < 3; attempt++) {
        try { await transcribeRecordingChunk(this.ownerId, chunk, this.cloud.signal); return; }
        catch (error) { if (this.cloud.signal.aborted || attempt === 2 || (error instanceof MeetingTranscriptionError && !error.retryable)) throw error; await new Promise<void>((resolve) => setTimeout(resolve, 1000 * (attempt + 1))); }
      }
    }).catch(() => { this.transcriptionFailed = true; this.error = 'Some recording speech needs retry. Its timed audio is retained in this browser.'; this.emit(); }).finally(() => { this.pendingTranscription--; });
  }
  private storageFailure(): void { this.captureFailed = true; this.error = "Storage filled or became unavailable. Recording stopped; earlier saved parts are retained."; if (!this.stopPromise) void this.stop(); }
  /** Stop is synchronous at the capture boundary and idempotent across leave, kick and unmount. */
  stop(cancelCloud = false): Promise<void> {
    if (cancelCloud) this.cloud.abort();
    if (this.stopPromise) return this.stopPromise;
    this.stopping = true;
    let finish!: () => void;
    this.stopPromise = new Promise<void>((resolve) => { finish = resolve; });
    const duration = this.seconds; this.finalSeconds = duration; this.state = "saving";
    this.startupAbort.abort(); this.disconnectInputs(); this.emit();
    if (this.timer) clearInterval(this.timer); this.timer = null;
    this.disconnectInputs();
    const slowDrain = setTimeout(() => { this.error = "Capture has stopped. Still saving the final audio and video—keep this tab open."; this.emit(); }, 4000);
    const media = this.recorder;
    const drainMedia = new Promise<void>((resolve) => { if (!media || media.state === "inactive") { resolve(); return; } const timer = setTimeout(() => { this.captureFailed = true; this.error = "The final media slice did not arrive. Earlier saved parts are retained."; resolve(); }, 30000); media.addEventListener("stop", () => { clearTimeout(timer); resolve(); }, { once: true }); try { media.stop(); } catch { clearTimeout(timer); this.captureFailed = true; this.error = "The browser could not finalize this recording. Earlier saved parts are retained."; resolve(); } });
    const drainPCM = new Promise<void>((resolve) => { if (!this.pcm || !this.captureStarted) { resolve(); return; } const timer = setTimeout(() => { this.captureFailed = true; this.error = "The final transcript audio did not arrive. Saved recording parts are retained."; resolve(); }, 30000); this.stoppedPCM = () => { clearTimeout(timer); resolve(); }; try { this.pcm.port.postMessage("stop"); } catch { clearTimeout(timer); this.captureFailed = true; this.error = "The last backup audio could not be finalized. Earlier pieces are retained."; resolve(); } });
    void (async () => {
      await Promise.all([drainMedia, drainPCM, this.speakerCapture?.stop()]);
      if (this.speakerCapture?.isIncomplete) { this.transcriptionFailed = true; this.error = 'Some final speaker audio was not received. Playback is retained, but the transcript may have gaps.'; }
      this.speakerCapture = null;
      clearTimeout(slowDrain);
      if (this.error?.startsWith("Capture has stopped.")) this.error = null;
      this.acceptingChunks = false;
      if (!this.wallStart) this.release();
      await this.startPromise?.catch(() => undefined);
      await this.writes; this.release();
      // Make media playable without waiting on cloud latency. The durably queued transcript continues independently.
      if (this.pendingTranscription) { this.error = 'Audio saved. Finishing the recording transcript… Keep this tab open.'; this.emit(); }
      if (this.reserved && this.captureStarted && !this.captureFailed && this.mediaIndex > 0) {
        try { await verifyStoredRecording(this.ownerId, this.id, duration, this.mediaIndex); }
        catch { this.captureFailed = true; this.error = "Recording parts were retained, but playback could not be verified. Open Notebook to review or export the backup audio."; }
      }
      if (this.reserved) await editRecording(this.ownerId, this.id, (record) => ({ ...record, duration: Math.max(record.duration, duration), transcriptionState: !this.transcribeEnabled ? 'off' : this.pendingTranscription > 0 ? 'pending' : this.transcriptionFailed || this.cloud.signal.aborted || this.captureFailed ? 'incomplete' : 'complete', status: this.captureFailed || !this.captureStarted || !this.mediaIndex ? "interrupted" : "ready", warnings: this.error ? [...new Set([...record.warnings, this.error])].slice(-100) : record.warnings }));
      if (this.reserved && this.transcribeEnabled) {
        this.cloudFinalization = this.transcription.then(async () => {
          if (!this.transcriptionFailed && this.error?.startsWith('Audio saved.')) this.error = null;
          await editRecording(this.ownerId, this.id, (record) => ({ ...record, transcriptionState: this.transcriptionFailed || this.cloud.signal.aborted || this.captureFailed ? 'incomplete' : 'complete', warnings: record.warnings.filter((warning) => !warning.startsWith('Audio saved. Finishing')) }));
          this.emit();
        }).catch(() => { this.error = 'Audio saved. Transcript status could not be updated; reopen recording options.'; this.emit(); });
      }
      this.state = this.captureStarted && !this.captureFailed && this.mediaIndex > 0 ? "ready" : "error";
      if (this.state === "ready") {
        try { await attachFinalizedRecordingNote({ id: this.id, ownerId: this.ownerId, meetingId: this.meetingId, title: this.title, createdAt: this.createdAt || new Date().toISOString(), status: "ready" }); }
        catch { this.error = "Recording saved. Its note could not be added yet—open Notebook and retry. Your recording is retained."; }
      }
      this.emit();
    })().catch(() => { this.release(); this.state = "error"; this.error = "Some final recording data could not be saved. Check Recordings for retained parts."; this.emit(); }).finally(() => { clearTimeout(slowDrain); finish(); });
    return this.stopPromise;
  }
  private release(): void {
    if (this.recorder && this.recorder.state !== "inactive") { try { this.recorder.stop(); } catch { this.captureFailed = true; } }
    if (this.timer) clearInterval(this.timer); this.timer = null;
    this.disconnectInputs();
    if (this.recorder) { this.recorder.ondataavailable = null; this.recorder.onerror = null; }
    this.stoppedPCM = null;
    if (this.pcm) this.pcm.port.onmessage = null;
    try { this.pcm?.disconnect(); } catch { this.captureFailed = true; } this.pcm = null;
    try { this.mosaic?.dispose(); } catch { this.captureFailed = true; } this.mosaic = null;
    this.destination?.stream.getTracks().forEach((track) => { try { track.stop(); } catch { this.captureFailed = true; } }); this.destination = null;
    if (this.context) { this.context.onstatechange = null; void this.context.close().catch(() => undefined); } this.context = null;
  }
}
