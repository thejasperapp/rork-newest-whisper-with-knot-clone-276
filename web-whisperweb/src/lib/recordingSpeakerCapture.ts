import type { PipMosaicSource } from './meetPipMosaic';
import { pcmWav } from './meetingRecordingModel';

type Lane = { input: MediaStreamAudioSourceNode; node: AudioWorkletNode; silent: GainNode; finish: (() => void) | null; closing: Promise<void> | null };
/** Per-track PCM shares the recorder's audio clock. Names are source labels, not inferred diarization. */
export class RecordingSpeakerCapture {
  private lanes = new Map<MediaStreamTrack, Lane>();
  private draining: Promise<void>[] = [];
  private stopped = false;
  private incomplete = false;
  get isIncomplete(): boolean { return this.incomplete; }
  constructor(private readonly context: AudioContext, private readonly origin: number, private readonly chunk: (value: { blob: Blob; start: number; end: number; sourceId: string; speakerName: string }) => void) {}
  update(sources: (PipMosaicSource & { transcriptionStream?: MediaStream | null })[]): void {
    if (this.stopped) return;
    const tracks = new Map<MediaStreamTrack, PipMosaicSource>();
    for (const source of sources) for (const track of (source.transcriptionStream ?? source.stream)?.getAudioTracks() ?? []) if (track.readyState === 'live' && source.micOn !== false && !tracks.has(track)) tracks.set(track, source);
    for (const [track, lane] of this.lanes) if (!tracks.has(track)) { this.draining.push(this.close(lane)); this.lanes.delete(track); }
    for (const [track, source] of tracks) {
      if (this.lanes.has(track)) continue;
      const input = this.context.createMediaStreamSource(new MediaStream([track]));
      const node = new AudioWorkletNode(this.context, 'whisper-recording-pcm', { channelCount: 1, processorOptions: { chunkSeconds: 12 } });
      const silent = this.context.createGain(); silent.gain.value = 0;
      const lane: Lane = { input, node, silent, finish: null, closing: null };
      const sourceId = source.id.slice(0, 160); const speakerName = source.name.trim().slice(0, 160) || 'Participant';
      node.port.onmessage = (event: MessageEvent<{ stopped?: boolean; samples?: Float32Array; rate: number; start: number; end: number }>) => {
        if (event.data.stopped) { lane.finish?.(); return; }
        const { samples, rate, start, end } = event.data;
        if (!samples?.length || !samples.some((value) => Math.abs(value) > 0.0005)) return;
        this.chunk({ blob: pcmWav(samples, rate), start: Math.max(0, start - this.origin), end: Math.max(0, end - this.origin), sourceId, speakerName });
      };
      input.connect(node); node.connect(silent); silent.connect(this.context.destination); node.port.postMessage('start');
      this.lanes.set(track, lane);
    }
  }
  private close(lane: Lane): Promise<void> {
    if (lane.closing) return lane.closing;
    lane.input.disconnect();
    lane.closing = new Promise<void>((resolve) => {
      const finish = (): void => { clearTimeout(timer); lane.node.port.onmessage = null; lane.node.disconnect(); lane.silent.disconnect(); resolve(); };
      const timer = setTimeout(() => { this.incomplete = true; finish(); }, 2000); lane.finish = finish;
      try { lane.node.port.postMessage('stop'); } catch { this.incomplete = true; finish(); }
    });
    return lane.closing;
  }
  stop(): Promise<void> {
    this.stopped = true;
    for (const lane of this.lanes.values()) this.draining.push(this.close(lane));
    this.lanes.clear(); return Promise.all(this.draining).then(() => undefined);
  }
}
