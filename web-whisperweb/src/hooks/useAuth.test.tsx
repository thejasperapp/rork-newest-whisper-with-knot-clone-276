import { act, cleanup, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import type { Session } from '@supabase/supabase-js';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
const mocks = vi.hoisted(() => ({ listener: null as ((event: string, session: Session | null) => void) | null, profiles: new Map<string, (value: unknown) => void>(), remember: vi.fn(), audience: vi.fn() }));
vi.mock('@/lib/supabase', () => ({ supabase: { auth: { getSession: async () => ({ data: { session: null } }), onAuthStateChange: (listener: typeof mocks.listener) => { mocks.listener = listener; return { data: { subscription: { unsubscribe() {} } } }; } }, from: () => { let id = ''; const query = { select() { return query; }, eq(_key: string, value: string) { id = value; return query; }, limit() { return query; }, maybeSingle() { return new Promise((resolve) => mocks.profiles.set(id, resolve)); } }; return query; } } }));
vi.mock('@/lib/ember', () => ({ setJasperAudience: mocks.audience }));
vi.mock('@/lib/accountSwitcher', () => ({ rememberSession: mocks.remember, forgetCurrentOnSignOut: vi.fn() }));
import { AuthProvider, useAuth } from './useAuth';
function Probe() { const auth = useAuth(); return <><p>{auth.user?.id ?? 'none'}:{auth.profile?.username ?? 'no-profile'}</p><p>{auth.loading ? 'loading' : auth.profileError ? 'profile-error' : 'profile-resolved'}</p><button onClick={() => void auth.refreshProfile()}>Retry profile</button></>; }
afterEach(() => { cleanup(); mocks.profiles.clear(); vi.clearAllMocks(); });
describe('profile generation isolation', () => {
  it('distinguishes a temporary profile failure from a successful missing profile and recovers', async () => {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(<QueryClientProvider client={client}><AuthProvider><Probe /></AuthProvider></QueryClientProvider>);
    await act(async () => {});
    await act(async () => mocks.listener?.('SIGNED_IN', { user: { id: 'A' } } as Session));
    await waitFor(() => expect(mocks.profiles.has('A')).toBe(true));
    await act(async () => mocks.profiles.get('A')?.({ data: null, error: { message: 'offline' } }));
    expect(screen.getByText('profile-error')).toBeInTheDocument();
    expect(mocks.remember).not.toHaveBeenCalled();
    const old = mocks.profiles.get('A');
    await act(async () => screen.getByRole('button', { name: 'Retry profile' }).click());
    await waitFor(() => expect(mocks.profiles.get('A')).not.toBe(old));
    await act(async () => mocks.profiles.get('A')?.({ data: null, error: null }));
    expect(screen.getByText('profile-resolved')).toBeInTheDocument();
    expect(screen.getByText('A:no-profile')).toBeInTheDocument();
  });
  it('keeps a good profile on failed same-account refresh and rejects outgoing errors', async () => {
    const client = new QueryClient();
    render(<QueryClientProvider client={client}><AuthProvider><Probe /></AuthProvider></QueryClientProvider>);
    await act(async () => {});
    await act(async () => mocks.listener?.('SIGNED_IN', { user: { id: 'A' } } as Session));
    await act(async () => mocks.profiles.get('A')?.({ data: { user_id: 'A', username: 'A-profile' } }));
    await act(async () => screen.getByRole('button', { name: 'Retry profile' }).click());
    const outgoing = mocks.profiles.get('A');
    await act(async () => mocks.profiles.get('A')?.({ data: null, error: { message: 'offline' } }));
    expect(screen.getByText('A:A-profile')).toBeInTheDocument();
    expect(screen.getByText('profile-error')).toBeInTheDocument();
    await act(async () => mocks.listener?.('SIGNED_IN', { user: { id: 'B' } } as Session));
    await act(async () => mocks.profiles.get('B')?.({ data: { user_id: 'B', username: 'B-profile' } }));
    await act(async () => outgoing?.({ data: null, error: { message: 'late failure' } }));
    expect(screen.getByText('B:B-profile')).toBeInTheDocument();
    expect(screen.getByText('profile-resolved')).toBeInTheDocument();
  });
  it('clears private queries on switching and sign-out, not token refresh', async () => {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(<QueryClientProvider client={client}><AuthProvider><Probe /></AuthProvider></QueryClientProvider>);
    await act(async () => {});
    await act(async () => mocks.listener?.('SIGNED_IN', { user: { id: 'A' } } as Session));
    client.setQueryData(['conversations', 'A'], ['private A']);
    await act(async () => mocks.listener?.('TOKEN_REFRESHED', { user: { id: 'A' } } as Session));
    expect(client.getQueryData(['conversations', 'A'])).toEqual(['private A']);
    await act(async () => mocks.listener?.('SIGNED_IN', { user: { id: 'B' } } as Session));
    expect(client.getQueryCache().getAll()).toHaveLength(0);
    client.setQueryData(['conversations', 'B'], ['private B']);
    await act(async () => mocks.listener?.('SIGNED_OUT', null));
    expect(client.getQueryCache().getAll()).toHaveLength(0);
  });

  it('does not let an outgoing network response repopulate the query cache', async () => {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(<QueryClientProvider client={client}><AuthProvider><Probe /></AuthProvider></QueryClientProvider>);
    await act(async () => {});
    await act(async () => mocks.listener?.('SIGNED_IN', { user: { id: 'A' } } as Session));
    let finish!: (value: string[]) => void;
    const pending = client.fetchQuery({ queryKey: ['conversations', 'A'], queryFn: () => new Promise<string[]>(resolve => { finish = resolve; }) }).catch(() => undefined);
    await act(async () => mocks.listener?.('SIGNED_IN', { user: { id: 'B' } } as Session));
    await act(async () => { finish(['private A']); await pending; });
    expect(client.getQueryCache().getAll()).toHaveLength(0);
  });
  it('discards an outgoing profile when it resolves after account switching', async () => {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(<QueryClientProvider client={client}><AuthProvider><Probe /></AuthProvider></QueryClientProvider>); await act(async () => {});
    await act(async () => mocks.listener?.('SIGNED_IN', { user: { id: 'A' } } as Session)); await waitFor(() => expect(mocks.profiles.has('A')).toBe(true));
    await act(async () => mocks.listener?.('SIGNED_IN', { user: { id: 'B' } } as Session)); await waitFor(() => expect(mocks.profiles.has('B')).toBe(true));
    await act(async () => mocks.profiles.get('B')?.({ data: { user_id: 'B', username: 'B-profile' } })); expect(screen.getByText('B:B-profile')).toBeInTheDocument();
    await act(async () => mocks.profiles.get('A')?.({ data: { user_id: 'A', username: 'A-profile' } })); expect(screen.getByText('B:B-profile')).toBeInTheDocument(); expect(mocks.remember).toHaveBeenCalledOnce(); expect(mocks.remember.mock.calls[0][0].user.id).toBe('B');
  });
});
