import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, describe, expect, it, vi } from 'vitest';
import type { WorkBoard, WorkView } from '@/lib/workspace';
const mocks = vi.hoisted(() => ({ request: vi.fn() }));
vi.mock('@/hooks/useAuth', () => ({ useAuth: () => ({ user: null }) }));
vi.mock('@/lib/jasperMeetings', () => ({ jasperMeetingRequest: mocks.request }));
vi.mock('@/components/JasperNoteConnections', () => ({ JasperNoteConnections: () => <p>Selected meeting connection draft</p> }));
vi.mock('@/components/JasperMeetingAssistant', () => ({ JasperMeetingAnswerCard: () => null }));
import { WorkspaceWorkBoard } from './WorkspaceWork';
import { WorkspaceItemDetail } from '@/components/WorkspaceItemDetail';
const owner = '10000000-0000-4000-8000-000000000001', scope = { space: owner, team: false };
const board: WorkBoard = { items: [], member: true, owner: true, canSubmit: true, intakeInstructions: 'Describe the work.', checkedAt: '2026-09-13T00:00:00Z' };
const item: WorkView = { id: '10000000-0000-4000-8000-000000000005', kind: 'delivery', title: 'Private title', brief: 'Private brief', internalNote: 'Internal context', alternatives: '', deadline: '', reviewOn: '', assigneeId: owner, createdBy: owner, requesterId: '', status: 'draft', outcome: '', category: '', priority: 'normal', revision: 1, createdAt: '', updatedAt: '', client: null, publishedVersion: null, versions: [], comments: [], events: [], external: false, canManage: true, canDecide: true, canRespond: false };
afterEach(() => { cleanup(); vi.clearAllMocks(); });
function setup(detail = false): QueryClient {
  const cache = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } });
  mocks.request.mockImplementation(async (_owner: string, path: string) => path.includes('clients/teams') ? { teams: [] } : path.includes('/members') ? { people: [{ id: owner, username: 'Owner' }] } : path.includes('/item/') ? item : board);
  render(<MemoryRouter><QueryClientProvider client={cache}>{detail ? <WorkspaceItemDetail owner={owner} scope={scope} id={item.id} members={[]} isOwner close={() => {}} /> : <WorkspaceWorkBoard owner={owner} scope={scope} navigate={() => {}} />}</QueryClientProvider></MemoryRouter>); return cache;
}
describe('workspace permission-sensitive drafts', () => {
  it('discards member creation approval after a requester downgrade', async () => {
    const cache = setup(); fireEvent.click(await screen.findByRole('button', { name: 'New request' })); fireEvent.click(screen.getByRole('checkbox'));
    await act(async () => cache.setQueryData(['jasper-work-board', owner, scope.space, false], { ...board, member: false, owner: false }));
    await waitFor(() => expect(screen.queryByRole('form')).not.toBeInTheDocument()); fireEvent.click(screen.getByRole('button', { name: 'New request' })); expect(screen.getByRole('checkbox')).not.toBeChecked(); expect(screen.queryByLabelText('Accountable owner / approver')).not.toBeInTheDocument();
  });
  it('removes requester creation when an invitation is revoked but delivery access remains', async () => {
    const cache = setup(); await screen.findByRole('button', { name: 'New request' }); await act(async () => cache.setQueryData(['jasper-work-board', owner, scope.space, false], { ...board, member: false, owner: false }));
    await screen.findByText(/You see only deliveries/); fireEvent.click(screen.getByRole('button', { name: 'New request' })); await act(async () => cache.setQueryData(['jasper-work-board', owner, scope.space, false], { ...board, member: false, owner: false, canSubmit: false }));
    await waitFor(() => expect(screen.queryByRole('form')).not.toBeInTheDocument()); expect(screen.queryByRole('button', { name: 'New request' })).not.toBeInTheDocument();
  });
  it('removes private editing and meeting context on successful member-to-client downgrade', async () => {
    const cache = setup(true); fireEvent.click(await screen.findByRole('button', { name: 'Edit brief' })); expect(screen.getByRole('form')).toBeInTheDocument();
    await act(async () => cache.setQueryData(['jasper-work-detail', owner, scope.space, false, item.id], { ...item, title: 'Published title', brief: 'Reviewed snapshot', internalNote: '', external: true, canManage: false, canDecide: false }));
    await waitFor(() => expect(screen.queryByRole('form')).not.toBeInTheDocument()); expect(screen.queryByText('Private brief')).not.toBeInTheDocument(); expect(screen.queryByRole('button', { name: 'Find meeting connections' })).not.toBeInTheDocument(); expect(screen.getByText('Reviewed snapshot')).toBeInTheDocument();
  });
});
