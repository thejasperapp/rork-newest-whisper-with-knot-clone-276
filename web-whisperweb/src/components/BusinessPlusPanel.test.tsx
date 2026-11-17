import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';
import { BusinessPlusPanel } from './BusinessPlusPanel';
import { fetchMyBusinessPlus, fetchTeam, removeTeamMember, type MyBusinessPlus } from '@/lib/businessPlus';
vi.mock('@/hooks/useAuth', () => ({ useAuth: () => ({ user: { id: 'owner' }, profile: { username: 'owner' }, loading: false }) }));
vi.mock('@/lib/businessPlus', async (load) => { const real = await load<typeof import('@/lib/businessPlus')>(); return { ...real, fetchMyBusinessPlus: vi.fn(), fetchTeam: vi.fn(), fetchPositions: vi.fn(async () => []), fetchQuestions: vi.fn(async () => []), fetchBusinessEvents: vi.fn(async () => []), removeTeamMember: vi.fn() }; });
vi.mock('@/lib/groupChats', () => ({ fetchMyGroupThreads: vi.fn(async () => []) }));
vi.mock('@/components/EmbeddedCheckoutSheet', () => ({ EmbeddedCheckoutSheet: () => null }));
vi.mock('@/components/GroupChats', () => ({ GroupThreadView: () => null }));
vi.mock('@/lib/supabase', () => ({ supabase: { auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }) }, from: () => ({ select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: null }) }) }) }) } }));
const me = { business: { id: 'plan', user_id: 'owner', plan: 'monthly', company_name: 'Test team' }, isOwner: true, roleTitle: 'Owner' } as MyBusinessPlus;
function setup() { const cache = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } }); render(<MemoryRouter><QueryClientProvider client={cache}><BusinessPlusPanel /></QueryClientProvider></MemoryRouter>); return cache; }
beforeEach(() => { vi.clearAllMocks(); vi.mocked(fetchMyBusinessPlus).mockResolvedValue(me); vi.mocked(fetchTeam).mockResolvedValue([{ business_id: 'owner', user_id: 'member', username: 'alex', role_title: 'Designer', accent: '#000000', added_at: null }]); });
describe('team entry and management', () => {
  it('offers retry rather than a checkout when membership cannot be checked', async () => { vi.mocked(fetchMyBusinessPlus).mockRejectedValue(new Error('Offline')); setup(); expect(await screen.findByRole('button', { name: 'Retry team access' })).toBeVisible(); expect(screen.queryByText('Add person')).not.toBeInTheDocument(); });
  it('requires confirmation before removing a teammate', async () => {
    vi.mocked(removeTeamMember).mockResolvedValue(undefined); setup(); await screen.findByText('@alex'); fireEvent.click(screen.getByRole('button', { name: 'Edit role' })); fireEvent.click(screen.getByRole('button', { name: 'Remove member' }));
    expect(await screen.findByRole('alertdialog')).toBeVisible(); expect(removeTeamMember).not.toHaveBeenCalled(); fireEvent.click(screen.getByRole('button', { name: 'Remove from team' })); await waitFor(() => expect(removeTeamMember).toHaveBeenCalledWith('owner', 'member'));
  });
  it('hides membership editing for non-owner teammates', async () => { vi.mocked(fetchMyBusinessPlus).mockResolvedValue({ ...me, isOwner: false, roleTitle: 'Designer' }); setup(); await screen.findByText('@alex'); expect(screen.queryByRole('button', { name: 'Add person' })).not.toBeInTheDocument(); expect(screen.queryByRole('button', { name: 'Edit role' })).not.toBeInTheDocument(); });
});
