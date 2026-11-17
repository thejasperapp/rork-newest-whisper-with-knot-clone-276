// @vitest-environment node
import { afterEach, describe, expect, it, vi } from 'vitest';
import { loginUsername, passwordLogin } from '../../functions/password-login';

const id = '00000000-0000-4000-8000-000000000001';
const account = { user_id: id, username: 'test_user' };
const json = (value: unknown, status = 200): Response => Response.json(value, { status });
const request = (identifier = '@Test_User', password = ' exact password '): Request => new Request('https://example.test/auth/password-login', {
  method: 'POST', headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '192.0.2.1' }, body: JSON.stringify({ identifier, password }),
});
const env = () => ({ SUPABASE_SERVICE_ROLE_KEY: 'server-test-key', EXPO_PUBLIC_SUPABASE_ANON_KEY: 'public-test-key', DO: { fetch: vi.fn(async (_request: Request) => new Response(null, { status: 204 })) } });
afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); });

describe('password login boundary', () => {
  it('normalizes exact handles, rejects patterns and non-handles', () => {
    expect(loginUsername(' @Test_User ')).toBe('test_user');
    expect(loginUsername('@JosÉ')).toBe('josé');
    for (const value of ['a%', 'a*', 'a,b', 'a@b.com', '+15551234567', '', 'x'.repeat(66), null]) expect(loginUsername(value)).toBeNull();
  });

  it('verifies the real password, binds returned identity and does not expose email', async () => {
    const fetcher = vi.fn().mockResolvedValueOnce(json([account])).mockResolvedValueOnce(json({ email: 'private@example.test' }))
      .mockResolvedValueOnce(json({ access_token: 'test-access', refresh_token: 'test-refresh', user: { id } }));
    vi.stubGlobal('fetch', fetcher);
    const settings = env();
    const response = await passwordLogin(request(), settings);
    expect(response.status).toBe(200);
    expect(response.headers.get('Cache-Control')).toBe('no-store');
    expect(await response.json()).toEqual({ access_token: 'test-access', refresh_token: 'test-refresh', user_id: id });
    const [lookup] = fetcher.mock.calls[0];
    expect(new URL(lookup).searchParams.get('username')).toBe('ilike.test\\_user');
    const [, grant] = fetcher.mock.calls[2];
    expect(JSON.parse(grant.body)).toEqual({ email: 'private@example.test', password: ' exact password ' });
    expect(grant.headers.apikey).toBe('public-test-key');
    for (const [attempt] of settings.DO.fetch.mock.calls) {
      expect(attempt.headers.get('X-Rork-DO-Id')).toMatch(/^[0-9a-f]{64}$/);
      expect(attempt.headers.get('X-Rork-DO-Class')).toBe('WhisperLoginLimiter');
      expect(await attempt.text()).toBe('');
    }
  });

  it.each([{ rows: [] }, { rows: [account, account] }, { rows: [{ ...account, username: 'testXuser' }] }])('rejects missing, ambiguous or nonexact handles', async ({ rows }) => {
    const fetcher = vi.fn().mockResolvedValue(json(rows));
    vi.stubGlobal('fetch', fetcher);
    const response = await passwordLogin(request(), env());
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: 'invalid_credentials' });
    expect(fetcher).toHaveBeenCalledTimes(1);
  });

  it('does not leak upstream verification errors or resolved emails', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValueOnce(json([account])).mockResolvedValueOnce(json({ email: 'private@example.test' }))
      .mockResolvedValueOnce(json({ msg: 'unconfirmed private@example.test' }, 400)));
    const response = await passwordLogin(request(), env());
    expect(response.status).toBe(401);
    expect(await response.text()).toBe('{"error":"invalid_credentials"}');
  });

  it('rejects sessions for an identity different from the lookup', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValueOnce(json([account])).mockResolvedValueOnce(json({ email: 'private@example.test' }))
      .mockResolvedValueOnce(json({ access_token: 'wrong', refresh_token: 'wrong', user: { id: 'other' } })));
    expect((await passwordLogin(request(), env())).status).toBe(401);
  });

  it('limits attempts before any account lookup', async () => {
    const settings = env(); settings.DO.fetch.mockResolvedValue(new Response(null, { status: 429 }));
    const fetcher = vi.fn(); vi.stubGlobal('fetch', fetcher);
    const response = await passwordLogin(request(), settings);
    expect(response.status).toBe(429);
    expect(response.headers.get('Retry-After')).toBe('900');
    expect(fetcher).not.toHaveBeenCalled();
  });

  it('fails closed if rate limiting is unavailable', async () => {
    const settings = env(); settings.DO.fetch.mockRejectedValue(new Error('offline'));
    const fetcher = vi.fn(); vi.stubGlobal('fetch', fetcher);
    expect((await passwordLogin(request(), settings)).status).toBe(503);
    expect(fetcher).not.toHaveBeenCalled();
  });

  it('distinguishes service outages from incorrect credentials', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(json({}, 503)));
    expect((await passwordLogin(request(), env())).status).toBe(503);
  });

  it('rejects oversized bodies and unsupported methods without upstream requests', async () => {
    const fetcher = vi.fn(); vi.stubGlobal('fetch', fetcher);
    expect((await passwordLogin(request('test_user', 'x'.repeat(9000)), env())).status).toBe(401);
    expect((await passwordLogin(new Request('https://example.test'), env())).status).toBe(405);
    expect(fetcher).not.toHaveBeenCalled();
  });
});
