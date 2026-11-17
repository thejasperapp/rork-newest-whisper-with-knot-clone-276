import { groupThemeSession } from '@/lib/groupThemeSession';
import { knotBackendOrigin } from '@/lib/knotBackend';
import { EmberRealtimeSession } from '@/lib/emberRealtime';
import { claimKnotVoiceAudio, releaseKnotVoiceAudio, knotVoiceAudioBusy } from '@/lib/knotAudioOwnership';
import { consentChanged, type KnotBot } from '@/lib/knotService';
import type { KnotWelcomeAnswer } from '@/lib/knotWelcome';

export const knotVoiceConsent = 'knot_rork_elevenlabs_voice_consent_v2';
export interface KnotVoiceContext { bot: KnotBot; preferences: string; profile: string; recentConversation: string }
type Callbacks = {
  onState?: (state: 'live' | 'closed' | 'error') => void;
  onUserSpeech?: (active: boolean) => void;
  onUserTranscript?: (text: string, final: boolean) => void;
  onAssistantDone?: (text: string) => void;
  onSpeaking?: (active: boolean) => void;
};
type Token = { token: string; prompt: string; voiceID: string; firstMessage: string; sessionID: string; provider: string; model: string; routingVersion: string };
const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;

/** ElevenLabs owns speech transport only. All Knot answers use the server's
 * signed identity and shared Rork model; never the legacy realtime provider.
 * No tools, retry, resumable sessions, provider-body logging or saved audio. */
export class KnotVoiceSession {
  static get isBusy(): boolean { return knotVoiceAudioBusy() || EmberRealtimeSession.isBusy; }
  private frame: HTMLIFrameElement | null = null;
  private frameChannel: string | null = null;
  private frameMessage: ((event: MessageEvent) => void) | null = null;
  private controller = new AbortController();
  private auth: Awaited<ReturnType<typeof groupThemeSession>> | null = null;
  private sessionID: string | null = null;
  private started = false;
  private closed = false;
  private muted = false;
  private lifetime: ReturnType<typeof setTimeout> | undefined;
  private startup: ReturnType<typeof setTimeout> | undefined;
  private seen = new Set<string>();
  constructor(private options: { owner: string; context?: KnotVoiceContext; welcome?: KnotWelcomeAnswer; signal?: AbortSignal; callbacks: Callbacks }) {}
  private check(): void {
    this.auth?.check();
    if (this.closed || this.controller.signal.aborted || this.options.signal?.aborted || document.hidden) throw new DOMException('Voice ended', 'AbortError');
  }
  private stop = (): void => this.close();
  private hidden = (): void => { if (document.hidden) this.close(); };
  private stored = (event: StorageEvent): void => { if (event.key === null || event.key.startsWith('knot_ai_consent_v3:' + this.options.owner.toLowerCase())) this.close(); };
  private error(): void { if (!this.closed) { this.close(false); this.options.callbacks.onState?.('error'); } }
  private endLease(id: string, token: string): void {
    // Original account credential only: never obtain/adopt a new account session.
    void fetch(knotBackendOrigin + '/knot/voice/end', { method: 'POST', cache: 'no-store', redirect: 'error', keepalive: true,
      headers: { 'Content-Type': 'application/json', 'X-Whisper-Authorization': `Bearer ${token}` },
      body: JSON.stringify({ sessionID: id }), signal: AbortSignal.timeout(5000),
    }).then(response => response.body?.cancel()).catch(() => undefined);
  }
  private startTransport(token: Token): Promise<void> {
    this.check();
    const frame = document.createElement('iframe'), channel = crypto.randomUUID();
    frame.src = '/knot-voice-transport.html#' + channel;
    frame.title = 'Knot audio transport'; frame.hidden = true;
    frame.allow = 'microphone; autoplay';
    this.frame = frame; this.frameChannel = channel;
    return new Promise<void>((resolve, reject) => {
      let sent = false;
      const abort = (): void => reject(new DOMException('Voice ended', 'AbortError'));
      this.controller.signal.addEventListener('abort', abort, { once: true });
      this.frameMessage = event => {
        if (this.closed || event.source !== frame.contentWindow || event.origin !== window.location.origin || event.data?.channel !== channel) return;
        const { type, value } = event.data as { type?: unknown; value?: unknown };
        if (type === 'ready' && !sent) {
          try {
            this.check(); sent = true;
            frame.contentWindow?.postMessage({ channel, type: 'start', value: { token: token.token, prompt: token.prompt, voiceID: token.voiceID, firstMessage: token.firstMessage } }, window.location.origin);
          } catch { this.error(); }
        } else if (type === 'started' && sent) {
          this.controller.signal.removeEventListener('abort', abort);
          frame.contentWindow?.postMessage({ channel, type: 'mute', value: this.muted }, window.location.origin);
          resolve();
        } else if (type === 'error') this.error();
        else if (type === 'closed') this.close();
        else if (type === 'speaking' && typeof value === 'boolean') this.options.callbacks.onSpeaking?.(value);
        else if (type === 'speech' && typeof value === 'boolean') this.options.callbacks.onUserSpeech?.(value);
        else if (type === 'message' && value && typeof value === 'object') {
          const message = value as { role?: unknown; message?: unknown; eventID?: unknown };
          if (!['user', 'agent'].includes(String(message.role)) || typeof message.message !== 'string' || message.message.length > 32000 || !Number.isSafeInteger(message.eventID)) { this.error(); return; }
          const id = message.role + ':' + message.eventID; if (this.seen.has(id)) return;
          if (this.seen.size >= 1000) { this.error(); return; }
          this.seen.add(id);
          if (message.role === 'user') this.options.callbacks.onUserTranscript?.(message.message, true);
          else this.options.callbacks.onAssistantDone?.(message.message);
        }
      };
      window.addEventListener('message', this.frameMessage);
      document.body.append(frame);
    });
  }
  async connect(): Promise<void> {
    if (this.started || this.closed || KnotVoiceSession.isBusy || !claimKnotVoiceAudio(this)) throw new Error('Another voice call is already open.');
    this.started = true;
    document.addEventListener('visibilitychange', this.hidden);
    window.addEventListener('pagehide', this.stop);
    window.addEventListener(consentChanged, this.stop);
    window.addEventListener('storage', this.stored);
    this.options.signal?.addEventListener('abort', this.stop, { once: true });
    this.startup = setTimeout(() => this.error(), 30000);
    this.lifetime = setTimeout(() => this.close(), 20 * 60 * 1000);
    try {
      this.check();
      // Resolve the browser's permission before requesting a one-use call token.
      // The maintained SDK then owns its own real microphone capture.
      const microphone = await navigator.mediaDevices.getUserMedia({ audio: true });
      microphone.getTracks().forEach(track => track.stop()); this.check();
      const auth = await groupThemeSession(this.options.owner);
      if (this.closed) { auth.dispose(); throw new DOMException('Voice ended', 'AbortError'); }
      this.auth = auth; auth.signal.addEventListener('abort', this.stop, { once: true }); this.check();
      const context = this.options.context ?? { bot: 'main', preferences: '', profile: '', recentConversation: '' };
      const signal = AbortSignal.any([this.controller.signal, auth.signal, AbortSignal.timeout(20000), ...(this.options.signal ? [this.options.signal] : [])]);
      const response = await fetch(knotBackendOrigin + '/knot/voice/token', { method: 'POST', cache: 'no-store', redirect: 'error', signal,
        headers: { 'Content-Type': 'application/json', 'X-Whisper-Authorization': `Bearer ${auth.token}` },
        body: JSON.stringify({ ...context, ...(this.options.welcome ?? {}), platform: 'web', voice: 'boy', consentVersion: knotVoiceConsent }),
      });
      if (!response.ok || !response.body) { await response.body?.cancel(); throw new Error('Voice unavailable'); }
      const reader = response.body.getReader(); let text = '', bytes = 0; const decoder = new TextDecoder();
      try {
        for (;;) { const part = await reader.read(); if (part.done) break; bytes += part.value.byteLength; if (bytes > 220000) throw new Error('Voice unavailable'); text += decoder.decode(part.value, { stream: true }); }
      } finally { await reader.cancel().catch(() => undefined); reader.releaseLock(); }
      const result = JSON.parse(text + decoder.decode()) as Partial<Token>;
      if (typeof result.sessionID === 'string' && uuid.test(result.sessionID)) {
        if (this.closed) this.endLease(result.sessionID, auth.token); else this.sessionID = result.sessionID;
      }
      this.check();
      if (result.routingVersion !== 'knot_rork_voice_v2' || result.provider !== 'rork' || typeof result.model !== 'string' || !result.model || !this.sessionID ||
          typeof result.token !== 'string' || result.token.length < 20 || result.token.length > 20000 || typeof result.prompt !== 'string' || result.prompt.length > 180000 || !/^\[KNOT_VOICE_V2\./.test(result.prompt) ||
          typeof result.voiceID !== 'string' || result.voiceID.length > 120 || typeof result.firstMessage !== 'string' || result.firstMessage.length > 2000) throw new Error('Voice routing unavailable');
      await this.startTransport(result as Token);
      this.check(); clearTimeout(this.startup); this.options.callbacks.onState?.('live');
    } catch { this.error(); throw new Error('Knot voice could not connect.'); }
  }
  setMicEnabled(enabled: boolean): void {
    if (this.closed) return;
    this.muted = !enabled;
    this.frame?.contentWindow?.postMessage({ channel: this.frameChannel, type: 'mute', value: !enabled }, window.location.origin);
  }
  close(notify = true): void {
    if (this.closed) return;
    this.closed = true;
    // Destroy the SDK's entire media context even if its factory has not
    // resolved. No global track sweep, uncertain adoption or awaited shutdown.
    if (this.frameMessage) window.removeEventListener('message', this.frameMessage);
    this.frameMessage = null; this.frame?.remove(); this.frame = null; this.frameChannel = null;
    this.controller.abort(); clearTimeout(this.startup); clearTimeout(this.lifetime);
    document.removeEventListener('visibilitychange', this.hidden); window.removeEventListener('pagehide', this.stop);
    window.removeEventListener(consentChanged, this.stop); window.removeEventListener('storage', this.stored);
    this.options.signal?.removeEventListener('abort', this.stop);
    const auth = this.auth; this.auth = null;
    auth?.signal.removeEventListener('abort', this.stop); auth?.dispose();
    if (auth && this.sessionID) this.endLease(this.sessionID, auth.token);
    this.sessionID = null;
    releaseKnotVoiceAudio(this);
    this.seen.clear(); this.options.callbacks.onSpeaking?.(false); this.options.callbacks.onUserSpeech?.(false);
    if (notify) this.options.callbacks.onState?.('closed');
  }
}
