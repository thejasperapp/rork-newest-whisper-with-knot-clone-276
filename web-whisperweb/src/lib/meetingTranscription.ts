import { supabase } from '@/lib/supabase';
import { JASPER_MEETINGS_URL } from '@/lib/jasperMeetings';
import workletURL from './recordingPCM.worklet.js?url';
import { pcmWav } from './meetingRecordingModel';

/** Capture time belongs to the microphone, never the time a network response arrives. */
export type SpeechCaptureTime = { spokenAt: string };
export interface MeetingRecorderTranscriber {
  stop: () => Promise<void>;
  readonly isActive: boolean;
  readonly isStarting: boolean;
  readonly trackId: string;
}

/** Safe, actionable messages shared by live captions and saved-audio retries. */
export class MeetingTranscriptionError extends Error {
  constructor(message: string, readonly retryable: boolean) { super(message); }
}
export function transcriptionFailure(status: number): MeetingTranscriptionError {
  if (status === 401 || status === 403) return new MeetingTranscriptionError('Your sign-in needs refreshing. Rejoin with your account to resume transcription.', false);
  if (status === 400 || status === 413 || status === 422) return new MeetingTranscriptionError('This audio segment could not be read. Retry capture to start a fresh audio segment.', false);
  if (status === 503) return new MeetingTranscriptionError('The transcription service is not configured or temporarily unavailable. Your meeting audio is unaffected.', false);
  return new MeetingTranscriptionError(status === 429 ? 'Transcription is busy. Retrying the captured audio…' : 'Transcription lost its connection. Retrying the captured audio…', true);
}

/** Uses only the authenticated project endpoint; never silently falls through an auth failure. */
export async function transcribeSpeechChunk(blob: Blob, ownerId?: string): Promise<string> {
  if (blob.size < 800) return '';
  const { data } = await supabase.auth.getSession();
  if (!data.session || (ownerId && data.session.user.id !== ownerId)) throw transcriptionFailure(401);
  const bytes = new Uint8Array(await blob.arrayBuffer()); let binary = '';
  for (let i = 0; i < bytes.length; i += 8192) binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
  const response = await fetch(`${JASPER_MEETINGS_URL}/ai/transcribe`, {
    method: 'POST', signal: AbortSignal.timeout(40000),
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${data.session.access_token}`, 'X-Whisper-Authorization': `Bearer ${data.session.access_token}` },
    body: JSON.stringify({ audio: btoa(binary), mediaType: blob.type || 'audio/wav' }),
  });
  if (!response.ok) throw transcriptionFailure(response.status);
  const result = await response.json() as { text?: string };
  const current = await supabase.auth.getSession();
  if (current.data.session?.user.id !== data.session.user.id) throw transcriptionFailure(401);
  return result.text?.trim() ?? '';
}

/** Borrows the raw call microphone; does not acquire or stop any RTC track. */
export function startMeetingRecorderTranscription(input: {
  stream: MediaStream; ownerId?: string;
  onTranscript: (text: string, capture?: SpeechCaptureTime) => void;
  onError: (message: string) => void;
  onReady?: () => void;
}): MeetingRecorderTranscriber | null {
  const track = input.stream.getAudioTracks().find((item) => item.enabled && item.readyState === 'live');
  if (!track || typeof AudioContext === 'undefined' || typeof AudioWorkletNode === 'undefined') return null;
  let context: AudioContext;
  try { context = new AudioContext(); } catch { return null; }
  let origin = 0;
  let node: AudioWorkletNode | null = null, source: MediaStreamAudioSourceNode | null = null;
  let active = false, starting = true, stopped = false, pending = 0;
  let cancelSetup: (() => void) | null = null;
  let setupTimer: ReturnType<typeof setTimeout> | undefined;
  const setupDeadline = new Promise<never>((_, reject) => {
    cancelSetup = () => reject(new Error('capture_cancelled'));
    setupTimer = setTimeout(() => reject(new Error('capture_setup_timeout')), 5000);
  });
  let queue: Promise<void> = Promise.resolve();
  let drained: (() => void) | null = null;
  let lastError = '';
  const report = (message: string): void => { if (message !== lastError) { lastError = message; input.onError(message); } };
  const process = (blob: Blob, start: number): void => {
    // Bound volatile recovery; no silent claim that audio survives closing the tab.
    if (pending >= 30) { report('Transcription recovery is full. Some speech may be missing. Keep the call open and restore the connection.'); return; }
    pending++;
    queue = queue.then(async () => {
      for (let attempt = 0; attempt < 3; attempt++) {
        try {
          const text = await transcribeSpeechChunk(blob, input.ownerId);
          if (text) input.onTranscript(text, { spokenAt: new Date(origin + start * 1000).toISOString() });
          lastError = ''; return;
        } catch (error) {
          if (error instanceof MeetingTranscriptionError && !error.retryable) throw error;
          if (attempt === 2) throw error;
          report('Transcription is catching up. Keep this tab open while captured speech retries.');
          await new Promise<void>((resolve) => setTimeout(resolve, 1000 * (attempt + 1)));
        }
      }
    }).catch((error: unknown) => report(error instanceof MeetingTranscriptionError ? error.message : 'A speech segment could not be transcribed after retry. Your call remains connected; the transcript has a gap.')).finally(() => { pending--; });
  };
  const setup = (async (): Promise<void> => {
    try {
      await Promise.race([context.resume(), setupDeadline]);
      if (stopped) return;
      await Promise.race([context.audioWorklet.addModule(workletURL), setupDeadline]);
      if (stopped) return;
      source = context.createMediaStreamSource(new MediaStream([track]));
      node = new AudioWorkletNode(context, 'whisper-recording-pcm', { channelCount: 1, processorOptions: { chunkSeconds: 8 } });
      const silent = context.createGain(); silent.gain.value = 0;
      source.connect(node); node.connect(silent); silent.connect(context.destination);
      node.port.onmessage = (event: MessageEvent<{ samples?: Float32Array; rate: number; start: number; stopped?: boolean }>) => {
        if (event.data.stopped) { drained?.(); return; }
        const samples = event.data.samples;
        if (samples?.length && samples.some((sample) => Math.abs(sample) > 0.0005)) process(pcmWav(samples, event.data.rate), event.data.start);
      };
      origin = Date.now() - context.currentTime * 1000;
      node.onprocessorerror = () => { active = false; source?.disconnect(); report('Microphone transcription was interrupted. Retry capture; the call is still connected.'); };
      node.port.postMessage('start');
      active = true; input.onReady?.();
    } catch {
      active = false;
      source?.disconnect(); node?.disconnect();
      void context.close().catch(() => undefined);
      if (!stopped) report('Microphone transcription could not start. Restore call audio and retry capture.');
    } finally { starting = false; clearTimeout(setupTimer); }
  })();
  const ended = (): void => { active = false; report('The call microphone changed. Reconnecting transcription…'); };
  track.addEventListener('ended', ended);
  context.onstatechange = () => { if (!stopped && context.state === 'suspended') { active = false; report('Transcription paused with the audio session. Return to the call and retry capture.'); } };
  let stopPromise: Promise<void> | null = null;
  return {
    get isActive(): boolean { return active && !stopped && track.readyState === 'live'; },
    get isStarting(): boolean { return starting && !stopped; }, trackId: track.id,
    stop: (): Promise<void> => {
      if (stopPromise) return stopPromise;
      stopped = true; active = false; source?.disconnect(); cancelSetup?.();
      stopPromise = (async (): Promise<void> => {
        await setup;
        if (node) await new Promise<void>((resolve) => { const timer = setTimeout(() => { report('The final microphone audio could not be confirmed. The transcript may have a gap.'); resolve(); }, 2000); drained = () => { clearTimeout(timer); resolve(); }; node!.port.postMessage('stop'); });
        if (node) { node.port.onmessage = null; node.onprocessorerror = null; }
        source?.disconnect(); node?.disconnect(); track.removeEventListener('ended', ended); context.onstatechange = null;
        await context.close().catch(() => undefined); await queue;
      })();
      return stopPromise;
    },
  };
}
