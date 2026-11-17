import { Conversation, type VoiceConversation } from '@elevenlabs/client';

// One disposable same-origin document per call. Removing it destroys capture,
// playback and pending SDK startup together, without patching global media APIs
// or touching another call's tracks. It never receives the account credential.
const channel = window.location.hash.slice(1);
if (window.parent !== window && /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(channel)) {
  let started = false, ended = false, muted = false;
  let active: VoiceConversation | null = null;
  const send = (type: string, value?: unknown): void => { if (!ended) window.parent.postMessage({ channel, type, value }, window.location.origin); };
  const end = (): void => {
    if (ended) return;
    ended = true;
    active?.setMicMuted(true);
    if (active) void active.endSession().catch(() => undefined);
    active = null;
  };
  const failure = (): void => { send('error'); end(); };
  window.addEventListener('pagehide', end, { once: true });
  window.addEventListener('message', event => {
    if (ended || event.source !== window.parent || event.origin !== window.location.origin || event.data?.channel !== channel) return;
    if (event.data.type === 'mute' && typeof event.data.value === 'boolean') {
      muted = event.data.value; active?.setMicMuted(muted); return;
    }
    if (event.data.type !== 'start' || started) return;
    started = true;
    const input = event.data.value as Record<string, unknown> | undefined;
    if (!input || typeof input.token !== 'string' || input.token.length < 20 || input.token.length > 20000 ||
        typeof input.prompt !== 'string' || input.prompt.length > 180000 || !input.prompt.startsWith('[KNOT_VOICE_V2.') ||
        typeof input.voiceID !== 'string' || input.voiceID.length > 120 || typeof input.firstMessage !== 'string' || input.firstMessage.length > 2000) { failure(); return; }
    void Conversation.startSession({ conversationToken: input.token, connectionType: 'webrtc', textOnly: false,
      overrides: { agent: { prompt: { prompt: input.prompt }, firstMessage: input.firstMessage }, tts: { voiceId: input.voiceID } },
      clientTools: {},
      onConversationCreated: conversation => {
        if (conversation.type !== 'voice') { failure(); return; }
        active = conversation;
        if (ended) { conversation.setMicMuted(true); void conversation.endSession().catch(() => undefined); }
        else conversation.setMicMuted(muted);
      },
      onDisconnect: () => { send('closed'); end(); }, onError: failure,
      onUnhandledClientToolCall: failure,
      onModeChange: ({ mode }) => { send('speaking', mode === 'speaking'); send('speech', false); },
      onVadScore: ({ vadScore }) => send('speech', !muted && vadScore > 0.5),
      onInterruption: () => send('speaking', false),
      onMessage: ({ role, message, event_id }) => {
        if (message.length > 32000) { failure(); return; }
        send('message', { role, message, eventID: event_id });
      },
    }).then(conversation => {
      if (ended) { conversation.setMicMuted(true); void conversation.endSession().catch(() => undefined); return; }
      active = conversation; conversation.setMicMuted(muted); send('started');
    }).catch(failure);
  });
  send('ready');
}
