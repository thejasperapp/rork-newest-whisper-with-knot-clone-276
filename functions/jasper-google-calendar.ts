import { jasperJSON, routeJasperMeetings, type JasperEnv } from './jasper-meetings';
import { meetingUUID } from './jasper-meeting-rules';

export type GoogleCalendarEnv = { GOOGLE_CALENDAR_CLIENT_ID?: string; GOOGLE_CALENDAR_CLIENT_SECRET?: string; GOOGLE_CALENDAR_REDIRECT_URI?: string };
type Store = { read<T>(key: string): T | undefined; write(key: string, value: unknown): void; remove(key: string): void };
type OAuthState = { owner: string; nonce: string; expires: number };
type Tokens = { access_token: string; refresh_token?: string; expires_at: number };
const b64 = (bytes: Uint8Array): string => btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const unb64 = (value: string): Uint8Array => Uint8Array.from(atob(value.replace(/-/g, '+').replace(/_/g, '/')), (char) => char.charCodeAt(0));
const encoder = new TextEncoder();
async function hmacKey(secret: string): Promise<CryptoKey> { return crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']); }
async function sign(state: OAuthState, secret: string): Promise<string> {
  const data = b64(encoder.encode(JSON.stringify(state)));
  const signature = await crypto.subtle.sign('HMAC', await hmacKey(secret), encoder.encode(data));
  return `${data}.${b64(new Uint8Array(signature))}`;
}
async function verify(raw: string, secret: string): Promise<OAuthState> {
  if (!raw || raw.length > 1000) throw new Error('invalid_state');
  const [data, signature] = raw.split('.');
  if (!await crypto.subtle.verify('HMAC', await hmacKey(secret), unb64(signature), encoder.encode(data))) throw new Error('invalid_state');
  const state = JSON.parse(new TextDecoder().decode(unb64(data))) as OAuthState;
  if (!meetingUUID.test(state.owner) || !meetingUUID.test(state.nonce) || !Number.isFinite(state.expires) || state.expires < Date.now()) throw new Error('expired_state');
  return state;
}
async function tokenKey(secret: string): Promise<CryptoKey> { return crypto.subtle.importKey('raw', await crypto.subtle.digest('SHA-256', encoder.encode(`jasper-calendar:${secret}`)), 'AES-GCM', false, ['encrypt', 'decrypt']); }
async function encrypt(tokens: Tokens, secret: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const data = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await tokenKey(secret), encoder.encode(JSON.stringify(tokens)));
  return `${b64(iv)}.${b64(new Uint8Array(data))}`;
}
async function decrypt(value: string, secret: string): Promise<Tokens> {
  const [iv, data] = value.split('.');
  const clear = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: unb64(iv) }, await tokenKey(secret), unb64(data));
  return JSON.parse(new TextDecoder().decode(clear)) as Tokens;
}
function configured(env: GoogleCalendarEnv): boolean { return !!env.GOOGLE_CALENDAR_CLIENT_ID && !!env.GOOGLE_CALENDAR_CLIENT_SECRET && /^https:\/\//.test(env.GOOGLE_CALENDAR_REDIRECT_URI ?? ''); }
function finishPage(success: boolean): Response {
  return new Response(`<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"><title>Jasper Calendar</title></head><body><main><h1>${success ? 'Google Calendar connected' : 'Calendar was not connected'}</h1><p>${success ? 'Return to Whisper and refresh Upcoming. Jasper can read your primary calendar; it cannot change your events.' : 'Return to Whisper and try connecting again. Use the Google account with the same email as your Whisper account. Existing notes and recordings are unchanged.'}</p></main></body></html>`, { status: success ? 200 : 400, headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer', 'Content-Security-Policy': "default-src 'none'; frame-ancestors 'none'", 'Set-Cookie': 'jasper_calendar_state=; Path=/jasper-meetings/google; HttpOnly; Secure; SameSite=Lax; Max-Age=0' } });
}
/** Public OAuth entry points accept only expiring signed state; no user ID from an unverified URL. */
export async function googlePublicRoute(request: Request, env: JasperEnv): Promise<Response> {
  try {
    if (!configured(env)) return finishPage(false);
    const state = await verify(new URL(request.url).searchParams.get('state') ?? '', env.GOOGLE_CALENDAR_CLIENT_SECRET!);
    return routeJasperMeetings(request, env, state.owner);
  } catch { return finishPage(false); }
}
export async function googleCalendarRoute(request: Request, env: JasperEnv, store: Store): Promise<Response> {
  const url = new URL(request.url), path = url.pathname;
  const secret = env.GOOGLE_CALENDAR_CLIENT_SECRET ?? '';
  if (path.endsWith('/status') && request.method === 'GET') return jasperJSON({ configured: configured(env), connected: !!store.read('google_tokens') });
  if (!configured(env) && path.endsWith('/disconnect') && request.method === 'POST') { store.write('google_generation', crypto.randomUUID()); store.remove('google_pending'); store.remove('google_tokens'); return jasperJSON({ disconnected: true, revoked: false }); }
  if (!configured(env)) return jasperJSON({ error: 'google_setup_required' }, 503);
  const redirect = env.GOOGLE_CALENDAR_REDIRECT_URI!;
  if (path.endsWith('/connect') && request.method === 'POST') {
    const owner = request.headers.get('X-Jasper-Owner')!;
    const nonce = crypto.randomUUID(), verifier = b64(crypto.getRandomValues(new Uint8Array(32)));
    const state = await sign({ owner, nonce, expires: Date.now() + 600000 }, secret);
    const email = request.headers.get('X-Jasper-Email')?.trim().toLowerCase();
    if (!email) return jasperJSON({ error: 'google_matching_email_required' }, 400);
    store.write('google_generation', nonce);
    store.write('google_pending', { nonce, verifier, email, expires: Date.now() + 600000 });
    const start = new URL(redirect); start.pathname = '/jasper-meetings/google/start'; start.search = ''; start.searchParams.set('state', state);
    return jasperJSON({ url: start.toString() });
  }
  if (path.endsWith('/start') && request.method === 'GET') {
    const rawState = url.searchParams.get('state') ?? '';
    const state = await verify(rawState, secret);
    const pending = store.read<{ nonce: string; verifier: string; email: string; expires: number }>('google_pending');
    if (!pending || pending.nonce !== state.nonce || pending.expires < Date.now()) return finishPage(false);
    const google = new URL('https://accounts.google.com/o/oauth2/v2/auth');
    Object.entries({ client_id: env.GOOGLE_CALENDAR_CLIENT_ID!, redirect_uri: redirect, response_type: 'code', scope: 'openid email https://www.googleapis.com/auth/calendar.events.readonly', access_type: 'offline', prompt: 'consent', state: rawState, code_challenge_method: 'S256', code_challenge: b64(new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(pending.verifier)))) }).forEach(([key, value]) => google.searchParams.set(key, value));
    return new Response(null, { status: 302, headers: { Location: google.toString(), 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer', 'Set-Cookie': `jasper_calendar_state=${state.nonce}; Path=/jasper-meetings/google; HttpOnly; Secure; SameSite=Lax; Max-Age=600` } });
  }
  if (path.endsWith('/callback') && request.method === 'GET') {
    try {
      const state = await verify(url.searchParams.get('state') ?? '', secret);
      const pending = store.read<{ nonce: string; verifier: string; email: string; expires: number }>('google_pending');
      const cookie = request.headers.get('Cookie')?.split(';').map((part) => part.trim()).find((part) => part.startsWith('jasper_calendar_state='))?.split('=')[1];
      if (!pending || pending.nonce !== state.nonce || pending.expires < Date.now() || cookie !== state.nonce) return finishPage(false);
      store.remove('google_pending');
      const code = url.searchParams.get('code'); if (!code || url.searchParams.has('error')) return finishPage(false);
      const response = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', signal: AbortSignal.timeout(15000), body: new URLSearchParams({ client_id: env.GOOGLE_CALENDAR_CLIENT_ID!, client_secret: secret, redirect_uri: redirect, code, code_verifier: pending.verifier, grant_type: 'authorization_code' }) });
      if (!response.ok) return finishPage(false);
      const tokens = await response.json() as { access_token?: string; refresh_token?: string; expires_in?: number; scope?: string };
      if (!tokens.access_token || !tokens.refresh_token || !tokens.scope?.split(' ').includes('https://www.googleapis.com/auth/calendar.events.readonly')) return finishPage(false);
      const identityResponse = await fetch('https://openidconnect.googleapis.com/v1/userinfo', { headers: { Authorization: `Bearer ${tokens.access_token}` }, signal: AbortSignal.timeout(10000) });
      if (!identityResponse.ok) return finishPage(false);
      const identity = await identityResponse.json() as { email?: string; email_verified?: boolean };
      if (!identity.email_verified || identity.email?.trim().toLowerCase() !== pending.email) return finishPage(false);
      const encrypted = await encrypt({ access_token: tokens.access_token, refresh_token: tokens.refresh_token, expires_at: Date.now() + (tokens.expires_in ?? 3600) * 1000 }, secret);
      if (store.read<string>('google_generation') !== state.nonce) return finishPage(false);
      store.write('google_tokens', encrypted);
      return finishPage(true);
    } catch { return finishPage(false); }
  }
  if (path.endsWith('/disconnect') && request.method === 'POST') {
    const saved = store.read<string>('google_tokens'); store.write('google_generation', crypto.randomUUID()); store.remove('google_pending'); store.remove('google_tokens');
    let revoked = false;
    try { if (saved) { const token = await decrypt(saved, secret); const response = await fetch('https://oauth2.googleapis.com/revoke', { method: 'POST', body: new URLSearchParams({ token: token.refresh_token ?? token.access_token }), signal: AbortSignal.timeout(10000) }); revoked = response.ok; } } catch { /* Local credentials are removed even when Google's revocation endpoint is unavailable. */ }
    return jasperJSON({ disconnected: true, revoked });
  }
  if (path.endsWith('/events') && request.method === 'GET') {
    const saved = store.read<string>('google_tokens'); if (!saved) return jasperJSON({ events: [], connected: false });
    let tokens: Tokens;
    try { tokens = await decrypt(saved, secret); } catch { return jasperJSON({ error: 'google_reconnect' }, 401); }
    if (tokens.expires_at < Date.now() + 60000) {
      const response = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', signal: AbortSignal.timeout(15000), body: new URLSearchParams({ client_id: env.GOOGLE_CALENDAR_CLIENT_ID!, client_secret: secret, refresh_token: tokens.refresh_token ?? '', grant_type: 'refresh_token' }) });
      if (!response.ok) return jasperJSON({ error: 'google_reconnect' }, 401);
      const refreshed = await response.json() as { access_token?: string; expires_in?: number };
      if (!refreshed.access_token) return jasperJSON({ error: 'google_reconnect' }, 401);
      tokens = { ...tokens, access_token: refreshed.access_token, expires_at: Date.now() + (refreshed.expires_in ?? 3600) * 1000 };
      // A disconnect during the refresh must not recreate the connection.
      const encrypted = await encrypt(tokens, secret);
      if (store.read<string>('google_tokens') !== saved) return jasperJSON({ error: 'google_reconnect' }, 409);
      store.write('google_tokens', encrypted);
    }
    const eventsURL = new URL('https://www.googleapis.com/calendar/v3/calendars/primary/events');
    Object.entries({ singleEvents: 'true', orderBy: 'startTime', timeMin: new Date().toISOString(), timeMax: new Date(Date.now() + 30 * 86400000).toISOString(), maxResults: '250' }).forEach(([key, value]) => eventsURL.searchParams.set(key, value));
    const response = await fetch(eventsURL, { headers: { Authorization: `Bearer ${tokens.access_token}` }, signal: AbortSignal.timeout(15000) });
    if (!response.ok) return jasperJSON({ error: response.status === 401 ? 'google_reconnect' : 'calendar_unavailable' }, 502);
    const data = await response.json() as { nextPageToken?: string; items?: { id: string; summary?: string; status?: string; start?: { dateTime?: string; date?: string }; end?: { dateTime?: string; date?: string }; hangoutLink?: string; htmlLink?: string }[] };
    return jasperJSON({ connected: true, partial: !!data.nextPageToken, events: (data.items ?? []).filter((event) => event.status !== 'cancelled').map((event) => ({ id: `google:${event.id}`, title: event.summary ?? 'Calendar event', start: event.start?.dateTime ?? event.start?.date ?? '', end: event.end?.dateTime ?? event.end?.date ?? '', allDay: !event.start?.dateTime, link: event.hangoutLink ?? event.htmlLink ?? '', source: 'Google Calendar' })) });
  }
  return jasperJSON({ error: 'not_found' }, 404);
}
