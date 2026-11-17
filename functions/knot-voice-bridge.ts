import { knotAITransport, type KnotAIEnv } from './knot-ai-transport';
import { knotBackendOrigin } from './knot-backend';

// This clone only. Provider settings must independently pass the exact URL gate;
// never retarget shared provider agents as a side effect of a source migration.
export const knotVoiceBridgeURL = knotBackendOrigin + '/knot/voice/completions';
export const knotVoiceRouting = 'knot_rork_voice_v2';
export type VoiceBridgeEnv = KnotAIEnv & {
  KNOT_VOICE_BRIDGE_SIGNING_KEY?: string;
  ELEVENLABS_KNOT_BRIDGE_SECRET_ID?: string;
  DO: { fetch(request: Request): Promise<Response> };
};
const encoder = new TextEncoder();
const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const hex = (bytes: ArrayBuffer) => Array.from(new Uint8Array(bytes), n => n.toString(16).padStart(2, '0')).join('');
async function key(secret: string, usage: ('sign' | 'verify')[]) {
  return crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, usage);
}
export async function knotVoiceProviderSecret(secret: string): Promise<string> {
  return hex(await crypto.subtle.sign('HMAC', await key(secret, ['sign']), encoder.encode('knot-voice-provider:v2')));
}
export async function knotVoiceBucket(secret: string, owner: string): Promise<string> {
  return hex(await crypto.subtle.sign('HMAC', await key(secret, ['sign']), encoder.encode('knot-voice:' + owner)));
}
export async function voiceLease(env: VoiceBridgeEnv, bucket: string, action: 'open' | 'check' | 'end', id: string, expires?: number, signal?: AbortSignal): Promise<boolean> {
  const response = await env.DO.fetch(new Request('https://internal/voice-lease/' + action, {
    method: 'POST', signal: AbortSignal.any([AbortSignal.timeout(4000), ...(signal ? [signal] : [])]),
    headers: { 'Content-Type': 'application/json', 'X-Rork-DO-Class': 'KnotResponseLimiter', 'X-Rork-DO-Id': bucket },
    body: JSON.stringify({ id, expires }),
  }));
  const accepted = response.ok; await response.body?.cancel(); return accepted;
}
type VoiceContext = { v: typeof knotVoiceRouting; id: string; bucket: string; expires: number; prompt: string; relay: boolean };
export async function signedVoicePrompt(env: VoiceBridgeEnv, owner: string, prompt: string, relay: boolean, signal: AbortSignal): Promise<{ prompt: string; sessionID: string }> {
  if (!env.KNOT_VOICE_BRIDGE_SIGNING_KEY) throw new Error('voice_unavailable');
  const context: VoiceContext = { v: knotVoiceRouting, id: crypto.randomUUID(), bucket: await knotVoiceBucket(env.KNOT_VOICE_BRIDGE_SIGNING_KEY, owner), expires: Date.now() + 1200000, prompt, relay };
  // A signed per-call envelope, not a credential granting tools or account access.
  // The bridge discards provider/client system instructions and recovers only this.
  const bytes = encoder.encode(JSON.stringify(context));
  const payload = btoa(Array.from(bytes, byte => String.fromCharCode(byte)).join('')).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  // Match the callback envelope and both clients' bounded token responses.
  // Reject oversized context before opening a lease, never silently truncate it.
  if (payload.length > 179000) throw new Error('voice_unavailable');
  const signature = hex(await crypto.subtle.sign('HMAC', await key(env.KNOT_VOICE_BRIDGE_SIGNING_KEY, ['sign']), encoder.encode('knot-voice-context:v2:' + payload)));
  if (!await voiceLease(env, context.bucket, 'open', context.id, context.expires, signal)) throw new Error('voice_unavailable');
  return { prompt: `[KNOT_VOICE_V2.${payload}.${signature}]`, sessionID: context.id };
}
export async function readVoiceJSON(source: { body: ReadableStream<Uint8Array> | null }, maximum: number): Promise<unknown> {
  const reader = source.body?.getReader(); if (!reader) throw new Error('missing_body');
  let count = 0, text = ''; const decoder = new TextDecoder();
  try {
    for (;;) { const part = await reader.read(); if (part.done) break; count += part.value.byteLength; if (count > maximum) throw new Error('oversized_body'); text += decoder.decode(part.value, { stream: true }); }
    return JSON.parse(text + decoder.decode()) as unknown;
  } finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
}
const object = (v: unknown): Record<string, unknown> => v && typeof v === 'object' && !Array.isArray(v) ? v as Record<string, unknown> : {};
const fail = (status: number) => Response.json({ error: 'voice_response_unavailable' }, { status, headers: { 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': '*' } });
/** Provider-only audio adapter. No arbitrary model, URL, system prompt, tools,
 * workspace execution or direct-provider fallback. Never log request/response bodies. */
export async function knotVoiceCompletions(request: Request, env: VoiceBridgeEnv): Promise<Response> {
  const secret = env.KNOT_VOICE_BRIDGE_SIGNING_KEY, transport = knotAITransport(env);
  if (!secret || !transport || !env.ELEVENLABS_KNOT_BRIDGE_SECRET_ID) return fail(503);
  const supplied = request.headers.get('X-Knot-Voice-Authorization');
  if (!supplied || !/^[0-9a-f]{64}$/.test(supplied)) return fail(401);
  const suppliedBytes = Uint8Array.from(supplied.match(/../g)!, v => parseInt(v, 16));
  if (!await crypto.subtle.verify('HMAC', await key(secret, ['verify']), suppliedBytes, encoder.encode('knot-voice-provider:v2'))) return fail(401);
  try {
    const input = object(await readVoiceJSON(request, 600000));
    if (input.stream !== true || !Array.isArray(input.messages) || input.messages.length < 1 || input.messages.length > 200) return fail(400);
    const system = input.messages.map(object).filter(m => m.role === 'system').map(m => typeof m.content === 'string' ? m.content : '').join('\n');
    const matches = [...system.matchAll(/\[KNOT_VOICE_V2\.([A-Za-z0-9_-]{1,180000})\.([0-9a-f]{64})\]/g)];
    if (matches.length !== 1) return fail(403);
    const [, payload, signature] = matches[0];
    if (!await crypto.subtle.verify('HMAC', await key(secret, ['verify']), Uint8Array.from(signature.match(/../g)!, v => parseInt(v, 16)), encoder.encode('knot-voice-context:v2:' + payload))) return fail(403);
    const decoded = atob(payload.replace(/-/g, '+').replace(/_/g, '/'));
    const context = object(JSON.parse(new TextDecoder().decode(Uint8Array.from(decoded, c => c.charCodeAt(0)))));
    if (context.v !== knotVoiceRouting || typeof context.id !== 'string' || !uuid.test(context.id) || typeof context.bucket !== 'string' || !/^[0-9a-f]{64}$/.test(context.bucket) || typeof context.prompt !== 'string' || context.prompt.length > 100000 || typeof context.relay !== 'boolean' || typeof context.expires !== 'number' || context.expires <= Date.now() || context.expires > Date.now() + 1200000) return fail(403);
    if (!await voiceLease(env, context.bucket, 'check', context.id, undefined, request.signal)) return fail(403);
    const messages: Record<string, unknown>[] = [{ role: 'system', content: context.prompt }];
    const calls = new Set<string>(), seenCalls = new Set<string>();
    for (const raw of input.messages) {
      const m = object(raw);
      if (m.role === 'system') continue;
      if (!['user', 'assistant', 'tool'].includes(String(m.role)) || (m.content !== null && (typeof m.content !== 'string' || m.content.length > 32000))) return fail(400);
      const clean: Record<string, unknown> = { role: m.role, content: m.content };
      if (m.tool_calls != null) {
        if (!context.relay || m.role !== 'assistant' || !Array.isArray(m.tool_calls) || m.tool_calls.length !== 1) return fail(400);
        const c = object(m.tool_calls[0]), f = object(c.function);
        if (c.type !== 'function' || typeof c.id !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(c.id) || seenCalls.has(c.id) || f.name !== 'ask_knot' || typeof f.arguments !== 'string' || f.arguments.length > 256) return fail(400);
        const argumentsValue: unknown = JSON.parse(f.arguments);
        if (!argumentsValue || typeof argumentsValue !== 'object' || Array.isArray(argumentsValue) || Object.keys(argumentsValue).length !== 0) return fail(400);
        calls.add(c.id); seenCalls.add(c.id); clean.tool_calls = [{ id: c.id, type: 'function', function: { name: 'ask_knot', arguments: '{}' } }];
      }
      if (m.role === 'tool') {
        if (!context.relay || typeof m.tool_call_id !== 'string' || !calls.delete(m.tool_call_id)) return fail(400);
        clean.tool_call_id = m.tool_call_id;
      }
      messages.push(clean);
    }
    if (calls.size || messages.length < 2) return fail(400);
    // Ignore provider-authored tool definitions: this is the only optional tool,
    // and it executes in the existing permission-gated native chat, never here.
    const tools = context.relay ? [{ type: 'function', function: { name: 'ask_knot', description: 'Delegate this finalized spoken request exactly once to the existing native Knot chat. Speak only its confirmed returned answer.', parameters: { type: 'object', properties: {}, required: [], additionalProperties: false }, strict: true } }] : [];
    const owned = new AbortController();
    const signal = AbortSignal.any([request.signal, owned.signal, AbortSignal.timeout(60000)]);
    const bucket = context.bucket, sessionID = context.id, expires = context.expires;
    let checking = false;
    const timer = setInterval(() => {
      if (checking || signal.aborted) return;
      checking = true;
      void (async () => {
        try {
          if (expires <= Date.now() || !await voiceLease(env, bucket, 'check', sessionID, undefined, signal)) owned.abort();
        } catch { owned.abort(); }
        finally { checking = false; }
      })();
    }, 1000);
    const cleanup = () => { clearInterval(timer); owned.abort(); };
    signal.addEventListener('abort', () => clearInterval(timer), { once: true });
    try {
      const upstream = await fetch(transport.chatURL, { method: 'POST', signal, redirect: 'manual',
        headers: { Authorization: `Bearer ${transport.token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ model: transport.model, stream: true, max_tokens: 1500, messages, ...(tools.length ? { tools, parallel_tool_calls: false } : {}) }),
      });
      if (!upstream.ok || !upstream.body || !upstream.headers.get('Content-Type')?.includes('text/event-stream')) { await upstream.body?.cancel(); cleanup(); return fail(503); }
      const reader = upstream.body.getReader();
      // Backpressure/cancellation stays attached to this exact request. End-call
      // revocation also stops an already-running answer; failures close, not retry.
      const stream = new ReadableStream<Uint8Array>({
        async pull(controller) {
          try {
            if (signal.aborted) throw new Error('voice_ended');
            const part = await reader.read();
            if (signal.aborted) throw new Error('voice_ended');
            if (part.done) { cleanup(); reader.releaseLock(); controller.close(); }
            else controller.enqueue(part.value);
          } catch {
            cleanup(); await reader.cancel().catch(() => {}); reader.releaseLock(); controller.error(new Error('voice_ended'));
          }
        },
        async cancel() { cleanup(); await reader.cancel().catch(() => {}); reader.releaseLock(); },
      });
      return new Response(stream, { headers: { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store, no-transform' } });
    } catch { cleanup(); return fail(503); }
  } catch { return fail(503); }
}
export async function knotVoiceEnd(request: Request, env: VoiceBridgeEnv, owner: string): Promise<Response> {
  try {
    const input = object(await readVoiceJSON(request, 1000));
    if (!env.KNOT_VOICE_BRIDGE_SIGNING_KEY || typeof input.sessionID !== 'string' || !uuid.test(input.sessionID)) return fail(400);
    if (!await voiceLease(env, await knotVoiceBucket(env.KNOT_VOICE_BRIDGE_SIGNING_KEY, owner), 'end', input.sessionID, undefined, request.signal)) return fail(503);
    return Response.json({ ok: true }, { headers: { 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': '*' } });
  } catch { return fail(503); }
}
