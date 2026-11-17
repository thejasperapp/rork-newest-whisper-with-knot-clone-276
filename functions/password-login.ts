const DATABASE = 'https://uryyyegnbtlmyhqlgndy.supabase.co';
const responseHeaders = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Pragma': 'no-cache', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'Content-Type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
type LoginEnv = { SUPABASE_SERVICE_ROLE_KEY?: string; EXPO_PUBLIC_SUPABASE_ANON_KEY?: string; DO: { fetch(request: Request): Promise<Response> } };
const reply = (body: unknown, status: number): Response => new Response(JSON.stringify(body), { status, headers: { ...responseHeaders, ...(status === 429 ? { 'Retry-After': '900' } : {}) } });
const invalid = (): Response => reply({ error: 'invalid_credentials' }, 401);

/** Accept exact handles only. No pattern wildcards, emails or phone-directory lookups. */
export function loginUsername(value: unknown): string | null {
  if (typeof value !== 'string' || value.length > 65) return null;
  const name = value.trim().replace(/^@/, '').toLowerCase();
  return /^[\p{L}\p{N}\p{M}_.]{1,64}$/u.test(name) ? name : null;
}

async function boundedBody(request: Request): Promise<unknown> {
  if (!request.body) throw new Error('invalid_body');
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    for (;;) {
      const part = await reader.read();
      if (part.done) break;
      length += part.value.byteLength;
      if (length > 8192) { await reader.cancel(); throw new Error('invalid_body'); }
      chunks.push(part.value);
    }
  } finally { reader.releaseLock(); }
  const data = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { data.set(chunk, offset); offset += chunk.byteLength; }
  return JSON.parse(new TextDecoder().decode(data));
}

async function bucket(secret: string, value: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const digest = await crypto.subtle.sign('HMAC', key, encoder.encode(value));
  return Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, '0')).join('');
}

async function admit(env: LoginEnv, secret: string, value: string, limit: number): Promise<boolean> {
  const id = await bucket(secret, value);
  const result = await env.DO.fetch(new Request('https://internal/attempt', {
    method: 'POST', headers: { 'X-Rork-DO-Class': 'WhisperLoginLimiter', 'X-Rork-DO-Id': id, 'X-Login-Limit': String(limit) },
  }));
  if (result.status === 429) return false;
  if (!result.ok) throw new Error('limiter_unavailable');
  return true;
}

/** Exchanges a username/password for a normal Supabase session; never mints admin sessions. */
export async function passwordLogin(request: Request, env: LoginEnv): Promise<Response> {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: responseHeaders });
  if (request.method !== 'POST') return reply({ error: 'method_not_allowed' }, 405);
  const secret = env.SUPABASE_SERVICE_ROLE_KEY;
  const anon = env.EXPO_PUBLIC_SUPABASE_ANON_KEY;
  if (!secret || !anon || !env.DO) return reply({ error: 'temporarily_unavailable' }, 503);
  let body: { identifier?: unknown; password?: unknown };
  try {
    const raw = await boundedBody(request);
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return invalid();
    body = raw;
  } catch { return invalid(); }
  const username = loginUsername(body.identifier);
  if (!username || typeof body.password !== 'string' || !body.password.length || body.password.length > 1024) return invalid();
  try {
    const ip = request.headers.get('CF-Connecting-IP') ?? 'unavailable';
    if (!await admit(env, secret, 'ip:' + ip, 60)) return reply({ error: 'too_many_attempts' }, 429);
    if (!await admit(env, secret, 'handle:' + username, 12)) return reply({ error: 'too_many_attempts' }, 429);
    const headers = { apikey: secret, Authorization: `Bearer ${secret}` };
    const url = new URL(`${DATABASE}/rest/v1/whisper_profiles`);
    url.searchParams.set('select', 'user_id,username');
    url.searchParams.set('username', 'ilike.' + username.replace(/_/g, '\\_'));
    url.searchParams.set('limit', '2');
    const rowsResponse = await fetch(url, { headers, signal: AbortSignal.timeout(8000) });
    if (!rowsResponse.ok) return reply({ error: 'temporarily_unavailable' }, 503);
    const rows = await rowsResponse.json() as { user_id?: string; username?: string }[];
    if (!Array.isArray(rows) || rows.length !== 1 || rows[0]?.username?.toLowerCase() !== username) return invalid();
    const id = rows[0].user_id;
    if (!id || !/^[0-9a-f-]{36}$/i.test(id)) return invalid();
    const userResponse = await fetch(`${DATABASE}/auth/v1/admin/users/${id}`, { headers, signal: AbortSignal.timeout(8000) });
    if (userResponse.status === 404) return invalid();
    if (!userResponse.ok) return reply({ error: 'temporarily_unavailable' }, 503);
    const user = await userResponse.json() as { email?: string };
    if (!user.email) return invalid();
    const grant = await fetch(`${DATABASE}/auth/v1/token?grant_type=password`, {
      method: 'POST', headers: { apikey: anon, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: user.email, password: body.password }), signal: AbortSignal.timeout(8000),
    });
    if (grant.status === 429) return reply({ error: 'too_many_attempts' }, 429);
    if (grant.status >= 500) return reply({ error: 'temporarily_unavailable' }, 503);
    if (!grant.ok) return invalid();
    const session = await grant.json() as { access_token?: string; refresh_token?: string; user?: { id?: string } };
    if (session.user?.id?.toLowerCase() !== id.toLowerCase() || !session.access_token || !session.refresh_token) return invalid();
    return reply({ access_token: session.access_token, refresh_token: session.refresh_token, user_id: id }, 200);
  } catch {
    // Do not log request bodies, resolved identities, credentials or upstream auth responses.
    return reply({ error: 'temporarily_unavailable' }, 503);
  }
}
