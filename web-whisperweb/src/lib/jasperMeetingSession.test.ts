import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
const auth = vi.hoisted(() => ({ owner: '10000000-0000-4000-8000-000000000001', listener: null as ((event: string, session: { user: { id: string }; access_token: string } | null) => void) | null }));
vi.mock('./supabase', () => ({ supabase: { auth: { getSession: async () => ({ data: { session: { user: { id: auth.owner }, access_token: 'test-token' } }, error: null }), onAuthStateChange: (callback: typeof auth.listener) => { auth.listener = callback; return { data: { subscription: { unsubscribe() {} } } }; } } } }));
function login(owner: string) { auth.owner = owner; auth.listener?.('SIGNED_IN', { user: { id: owner }, access_token: 'test-token' }); }
beforeEach(() => { vi.resetModules(); auth.owner = '10000000-0000-4000-8000-000000000001'; });
afterEach(() => vi.unstubAllGlobals());
describe('meeting and workspace request account generations', () => {
  it('rejects a late response after switching away and back to the same account', async () => {
    const { jasperMeetingRequest } = await import('./jasperMeetings');
    const owner = auth.owner;
    let resolve!: (response: Response) => void;
    const fetcher = vi.fn(() => new Promise<Response>((done) => { resolve = done; })); vi.stubGlobal('fetch', fetcher);
    const promise = jasperMeetingRequest(owner, 'workspace'); const failure = expect(promise).rejects.toThrow(/changed/);
    await vi.waitFor(() => expect(fetcher).toHaveBeenCalledOnce());
    login('10000000-0000-4000-8000-000000000002'); login(owner); resolve(Response.json({ private: 'old response' })); await failure;
    expect((fetcher.mock.calls[0] as unknown as [string, RequestInit])[1].signal?.aborted).toBe(true);
  });
  it('does not send a mutation for a different signed-in owner', async () => { const { jasperMeetingRequest } = await import('./jasperMeetings'); const fetcher = vi.fn(); vi.stubGlobal('fetch', fetcher); await expect(jasperMeetingRequest('10000000-0000-4000-8000-000000000002', 'workspace', { action: 'create' })).rejects.toThrow(/Sign in/); expect(fetcher).not.toHaveBeenCalled(); });
});
