import { knotBackendIdentity } from './knot-backend';
import { readKnotPersonaIdentity } from './knot-shell';

// Dedicated Knot delivery capabilities. No human actor, arbitrary recipient,
// notification text, or client-supplied URL is accepted by the delivery bridge.
export type KnotContactEnv = { SUPABASE_SERVICE_ROLE_KEY?: string; DO: { fetch(request: Request): Promise<Response> } };
const origin = 'https://knot.internal'; // DO dispatch only, never external routing.
const backend = knotBackendIdentity;
const bridge = 'https://uryyyegnbtlmyhqlgndy.supabase.co/functions/v1/whisper-knot-contact';
const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;
export type ContactTicket = { backend: typeof backend; owner: string; eventID: string; expires: number; signature: string };
async function signature(env: KnotContactEnv, owner: string, eventID: string, expires: number): Promise<string> {
  if (!env.SUPABASE_SERVICE_ROLE_KEY) throw new Error('contact_not_configured');
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(env.SUPABASE_SERVICE_ROLE_KEY), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const value = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(JSON.stringify(['knot-contact-v2', backend, owner, eventID, expires])));
  return Array.from(new Uint8Array(value), byte => byte.toString(16).padStart(2, '0')).join('');
}
export async function sendKnotContact(env: KnotContactEnv, owner: string, eventID: string, expires: number): Promise<'accepted' | 'suppressed'> {
  // Old bridges cannot redeem this backend's ticket. Never fall back to the
  // legacy authority or try a second claim after an ambiguous attempt.
  if (!await knotContactReady()) throw new Error('contact_delivery_unavailable');
  const ticket: ContactTicket = { backend, owner, eventID, expires, signature: await signature(env, owner, eventID, expires) };
  const result = await fetch(bridge, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(ticket), signal: AbortSignal.timeout(12000), redirect: 'manual' });
  const status = result.status; await result.body?.cancel();
  if (status === 204) return 'suppressed';
  if (status !== 200) throw new Error('contact_delivery_unavailable');
  return 'accepted';
}
export async function knotContactReady(): Promise<boolean> {
  try {
    const response = await fetch(bridge + '/health', { signal: AbortSignal.timeout(5000), redirect: 'manual' });
    if (response.status !== 200) { await response.body?.cancel(); return false; }
    const text = await response.text(); if (text.length > 4096) return false;
    const health = JSON.parse(text) as { ready?: boolean; ticketVersion?: number; backends?: unknown };
    return health.ready === true && health.ticketVersion === 2 && Array.isArray(health.backends) && health.backends.includes(backend);
  } catch { return false; }
}
/** Validate the narrow capability before routing to any account store. The
 * delivery bridge returns it unchanged; it never possesses the signing key. */
export async function knotContactClaimRoute(request: Request, env: KnotContactEnv): Promise<Response> {
  const denied = () => Response.json({ error: 'forbidden' }, { status: 403, headers: { 'Cache-Control': 'no-store' } });
  try {
    if (Number(request.headers.get('Content-Length') ?? 0) > 1500) return denied();
    const reader = request.body?.getReader(); if (!reader) return denied();
    const decoder = new TextDecoder(); let text = '', size = 0;
    try {
      for (;;) {
        const part = await reader.read(); if (part.done) break;
        size += part.value.byteLength; if (size > 1500) return denied();
        text += decoder.decode(part.value, { stream: true });
      }
    } finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
    const input = JSON.parse(text + decoder.decode()) as ContactTicket;
    if (!input || input.backend !== backend || typeof input.owner !== 'string' || !uuid.test(input.owner) || typeof input.eventID !== 'string' || !uuid.test(input.eventID) ||
        !Number.isSafeInteger(input.expires) || input.expires <= Date.now() || input.expires > Date.now() + 10 * 60000 ||
        typeof input.signature !== 'string' || !/^[0-9a-f]{64}$/.test(input.signature)) return denied();
    const expected = await signature(env, input.owner, input.eventID, input.expires);
    let difference = 0; for (let i = 0; i < 64; i++) difference |= expected.charCodeAt(i) ^ input.signature.charCodeAt(i);
    if (difference) return denied();
    const claimed = await env.DO.fetch(new Request(origin + '/internal/knot/contact-claim', { method: 'POST', headers: {
      'Content-Type': 'application/json', 'X-Knot-Owner': input.owner, 'X-Rork-DO-Class': 'KnotBackgroundAccount', 'X-Rork-DO-Id': input.owner,
    }, body: JSON.stringify({ eventID: input.eventID, expires: input.expires }) }));
    if (!claimed.ok) return claimed;
    const event = await claimed.json() as { bot?: string; [key: string]: unknown };
    // Display data is read only after a valid, consumed server claim. Never trust
    // ticket content for a title, or rename canonical routing/specialist identities.
    const persona = event.bot === 'main' ? await readKnotPersonaIdentity(env, input.owner, request.signal) : undefined;
    const name = persona?.name.trim();
    return Response.json({ ...event, ...(name && name.length <= 40 && !/[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/.test(name) ? { displayName: name } : {}) }, { headers: { 'Cache-Control': 'private, no-store' } });
  } catch { return denied(); }
}
export async function claimKnotIncomingVoice(env: KnotContactEnv, owner: string, invitationID: string, answerID: string, bot: string, signal: AbortSignal): Promise<{ title: string; text: string } | null> {
  const response = await env.DO.fetch(new Request(origin + '/internal/knot/voice-claim', { method: 'POST', signal, headers: {
    'Content-Type': 'application/json', 'X-Knot-Owner': owner.toLowerCase(), 'X-Rork-DO-Class': 'KnotBackgroundAccount', 'X-Rork-DO-Id': owner.toLowerCase(),
  }, body: JSON.stringify({ invitationID, answerID, bot }) }));
  if (!response.ok) { await response.body?.cancel(); return null; }
  const raw = await response.json() as { title: string; text: string };
  return typeof raw.title === 'string' && raw.title.length <= 120 && typeof raw.text === 'string' && raw.text.length <= 12000 ? raw : null;
}
