// Dedicated assistant notification bridge. Never accepts human webhook rows,
// arbitrary notification content, recipients, URLs, or a human actor identity.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import { create } from 'https://deno.land/x/djwt@v3.0.2/mod.ts';
const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false, autoRefreshToken: false } });
const team = Deno.env.get('APNS_TEAM_ID') ?? '', kid = Deno.env.get('APNS_KEY_ID') ?? '', topic = Deno.env.get('APNS_BUNDLE_ID') ?? '';
const pem = Deno.env.get('APNS_PRIVATE_KEY') ?? Deno.env.get('APNS_KEY_P8') ?? '';
const sandboxDefault = (Deno.env.get('APNS_USE_SANDBOX') ?? 'true') === 'true';
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'content-type', 'Access-Control-Allow-Methods': 'GET, POST, OPTIONS', 'Cache-Control': 'no-store' };
const json = (body: unknown, status = 200) => Response.json(body, { status, headers: cors });
const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;
const names: Record<string, string> = { main: 'Knot', writer: 'Writing Knot', researcher: 'Research Knot', planner: 'Planning Knot', social: 'Community Knot' };
let cached: { value: string; at: number } | undefined;
async function jwt(): Promise<string> {
  if (!team || !kid || !topic || !pem) throw new Error('not_configured');
  if (cached && Date.now() - cached.at < 50 * 60000) return cached.value;
  const bytes = Uint8Array.from(atob(pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\\n|\s/g, '')), char => char.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', bytes, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const value = await create({ alg: 'ES256', kid, typ: 'JWT' }, { iss: team, iat: Math.floor(Date.now() / 1000) }, key);
  cached = { value, at: Date.now() }; return value;
}
const legacyBackend = 'spotxaa2tx3bjiagxo5lh';
// Additive fixed authorities: preserve both existing deployments. Never derive
// a callback from ticket text, or retry a claim at another backend.
const claimAuthorities = {
  uf26aun6d49w1tsjsm2u9: 'https://uf26aun6d49w1tsjsm2u9-backend.rork.app/internal/knot/contact-claim',
  mayokn2749ag072e3uvbh: 'https://newest-whisper-with-knot-clone-t6ui3ur-backend.rork.app/internal/knot/contact-claim',
} as const;
type Ticket = { backend?: keyof typeof claimAuthorities; owner: string; eventID: string; expires: number; signature: string };
type Canonical = { owner: string; eventID: string; channel: 'call' | 'update' | 'completion'; bot: string; conversationID: string; expiresAt: number; displayName?: unknown };
type Device = { token: string; active?: boolean; sandbox?: boolean; environment?: string; bundle_id?: string };
Deno.serve(async request => {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  try {
    if (new URL(request.url).pathname.endsWith('/health') && request.method === 'GET') {
      await jwt();
      const { error } = await supabase.from('whisper_device_tokens').select('user_id').limit(0);
      if (error) throw new Error('not_ready');
      return json({ ready: true, ticketVersion: 2, backends: [legacyBackend, ...Object.keys(claimAuthorities)] });
    }
    if (request.method !== 'POST') return json({ error: 'not_found' }, 404);
    const reader = request.body?.getReader(); if (!reader) return json({ error: 'forbidden' }, 403);
    let body = '', size = 0; const decoder = new TextDecoder();
    try {
      for (;;) { const part = await reader.read(); if (part.done) break; size += part.value.length; if (size > 1500) return json({ error: 'forbidden' }, 403); body += decoder.decode(part.value, { stream: true }); }
    } finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
    const ticket = JSON.parse(body + decoder.decode()) as Ticket;
    if (!ticket || (ticket.backend !== undefined && (typeof ticket.backend !== 'string' || !Object.hasOwn(claimAuthorities, ticket.backend))) || typeof ticket.owner !== 'string' || !uuid.test(ticket.owner) || typeof ticket.eventID !== 'string' || !uuid.test(ticket.eventID) || typeof ticket.signature !== 'string' || !/^[0-9a-f]{64}$/.test(ticket.signature) || !Number.isSafeInteger(ticket.expires) || ticket.expires <= Date.now() || ticket.expires > Date.now() + 10 * 60000) return json({ error: 'forbidden' }, 403);
    // Backend identity remains bound into the selected server's v2 HMAC.
    // Absent-backend legacy tickets retain their one original claim endpoint.
    const claimURL = ticket.backend === undefined
      ? 'https://spotxaa2tx3bjiagxo5lh-backend.rork.app/internal/knot/contact-claim'
      : claimAuthorities[ticket.backend];
    const claim = await fetch(claimURL, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(ticket), redirect: 'manual', signal: AbortSignal.timeout(6000) });
    if (!claim.ok) { await claim.body?.cancel(); return json({ error: 'event_unavailable' }, 409); }
    const event = await claim.json() as Canonical;
    if (event.owner !== ticket.owner || event.eventID !== ticket.eventID || !['call', 'update', 'completion'].includes(event.channel) || !names[event.bot] || !uuid.test(event.conversationID) || event.expiresAt !== ticket.expires || event.expiresAt <= Date.now()) return json({ error: 'event_unavailable' }, 409);
    // Only this fixed authority's canonical main-agent claim can supply a private
    // nickname. Other backends and specialists retain their existing titles.
    const displayName = ticket.backend === 'mayokn2749ag072e3uvbh' && event.bot === 'main' && typeof event.displayName === 'string' && event.displayName.trim().length > 0 && event.displayName.length <= 40 && !/[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/.test(event.displayName) ? event.displayName.trim() : names[event.bot];
    const { data: identity, error: identityError } = await supabase.auth.admin.getUserById(event.owner);
    const bannedUntil: unknown = identity.user && 'banned_until' in identity.user ? identity.user.banned_until : undefined;
    if (identityError || identity.user?.id !== event.owner || (typeof bannedUntil === 'string' && Date.parse(bannedUntil) > Date.now())) return new Response(null, { status: 204, headers: cors });
    const { data: preferences, error: prefsError } = await supabase.from('whisper_notification_prefs').select('*').eq('user_id', event.owner).maybeSingle();
    if (prefsError) throw new Error('preferences_unavailable');
    if (preferences?.master_enabled === false || preferences?.quiet_mode === true || (event.channel === 'call' ? preferences?.missed_calls === false : preferences?.dms === false)) return new Response(null, { status: 204, headers: cors });
    let { data: tokens, error } = await supabase.from('whisper_device_tokens').select('*').eq('user_id', event.owner).eq('active', true);
    if (error?.code === '42703') ({ data: tokens, error } = await supabase.from('whisper_device_tokens').select('*').eq('user_id', event.owner));
    if (error) throw new Error('devices_unavailable');
    if (!tokens?.length) return new Response(null, { status: 204, headers: cors });
    const seen = new Set<string>();
    const devices = (tokens as Device[]).filter(device => {
      if (device.active === false || typeof device.token !== 'string' || !/^[a-f0-9]{32,256}$/i.test(device.token) || seen.has(device.token)) return false;
      seen.add(device.token); return true;
    }).slice(0, 20);
    if (!devices.length) return new Response(null, { status: 204, headers: cors });
    const authorization = await jwt();
    const results = await Promise.allSettled(devices.map(async device => {
      const sandbox = typeof device.sandbox === 'boolean' ? device.sandbox : device.environment ? device.environment === 'sandbox' : sandboxDefault;
      // Deliberately no BadDeviceToken cross-environment retry: an ambiguous
      // alert is consumed once rather than risking repeated interruptions.
      const response = await fetch(`https://${sandbox ? 'api.sandbox.push.apple.com' : 'api.push.apple.com'}/3/device/${device.token}`, {
        method: 'POST', signal: AbortSignal.timeout(6000), redirect: 'manual', headers: {
          authorization: `bearer ${authorization}`, 'apns-topic': device.bundle_id || topic, 'apns-push-type': 'alert', 'apns-priority': '10',
          'apns-expiration': String(Math.floor(event.expiresAt / 1000)), 'apns-collapse-id': 'knot-' + event.eventID, 'content-type': 'application/json',
        }, body: JSON.stringify({ aps: {
          alert: { title: displayName, body: event.channel === 'call' ? 'Would you like to talk about your update?' : event.channel === 'completion' ? 'Your task has finished. Open your chat to see the result.' : 'Your responsibility has a new update.' }, sound: 'default',
          category: event.channel === 'call' ? 'WHISPER_KNOT_INVITATION' : 'WHISPER_KNOT_UPDATE', 'thread-id': 'knot-' + event.bot,
        }, data: { kind: event.channel === 'call' ? 'knot_invitation' : 'knot_update', recipient_user_id: event.owner, bot: event.bot, conversation_id: event.conversationID, invitation_id: event.channel === 'call' ? event.eventID : '', event_id: event.eventID } }),
      });
      const status = response.status; await response.body?.cancel();
      if (status === 410) { await supabase.from('whisper_device_tokens').update({ active: false }).eq('user_id', event.owner).eq('token', device.token); return false; }
      if (status !== 200) throw new Error('apns_unavailable');
      return true;
    }));
    if (results.some(result => result.status === 'rejected')) throw new Error('delivery_unconfirmed');
    if (!results.some(result => result.status === 'fulfilled' && result.value)) return new Response(null, { status: 204, headers: cors });
    // APNs acceptance is not a device-delivery/read receipt.
    return json({ accepted: true });
  } catch { console.warn('knot_contact_unavailable'); return json({ error: 'contact_unavailable' }, 503); }
});
