import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { WorkspaceSearch } from './WorkspaceSearch';
import { fetchNotebookArchive } from '@/lib/notebookArchive';
import { listNotebookDocuments } from '@/lib/notebookStorage';
import { newNotebookDocument } from '@/lib/notebookDocument';
import type { WhisperMeeting } from '@/lib/meetings';

const state = vi.hoisted(() => ({ owner: '00000000-0000-4000-8000-000000000001', active: false, minimized: false, auth: null as null | ((event: string, session: { user: { id: string } } | null) => void) }));
vi.mock('@/hooks/useAuth', () => ({ useAuth: () => ({ user: { id: state.owner } }) }));
vi.mock('@/hooks/useMeetingHost', () => ({ useMeetingHost: () => ({ active: state.active ? { id: 'call' } : null, minimized: state.minimized }) }));
vi.mock('@/lib/supabase', () => ({ supabase: { auth: { onAuthStateChange: (callback: typeof state.auth) => { state.auth = callback; return { data: { subscription: { unsubscribe: vi.fn() } } }; } }, from: () => {
  const chain = { select: () => chain, eq: () => chain, order: () => chain, range: () => chain, abortSignal: () => Promise.resolve({ data: [{ id: 'person', recruiter_id: state.owner, prospect_display_name: 'Alex Person', status: 'interested' }], error: null }) }; return chain;
} } }));
vi.mock('@/lib/notebookArchive', () => ({ fetchNotebookArchive: vi.fn() }));
vi.mock('@/lib/notebookStorage', () => ({ listNotebookDocuments: vi.fn() }));
vi.mock('@/lib/meetingRecordingStorage', () => ({ listRecordings: () => Promise.resolve([]) }));
vi.mock('@/lib/recordingCloud', () => ({ listRecordingArchivePage: () => Promise.resolve({ items: [{ id: 'backup', recording_id: 'record', owner_id: state.owner, source_revision: 2, created_at: '2026-09-13', snapshot: { id: 'record', ownerId: state.owner, title: 'Recorded planning', transcript: [], revision: 2 } }], issues: 0 }) }));
vi.mock('@/lib/jasperMeetings', () => ({ jasperMeetingRequest: () => Promise.resolve({ teams: [] }) }));
vi.mock('@/lib/workspace', () => ({ workRequest: () => Promise.resolve({ items: [{ id: 'work', title: 'Delivery brief', kind: 'delivery', status: 'draft', deadline: '', updatedAt: '2026-09-13' }] }), workLink: () => 'http://localhost/work?id=work' }));
vi.mock('./WorkspaceObjectView', () => ({ WorkspaceObjectView: ({ target }: { target: { kind: string; objectID: string; archiveID?: string } }) => <div data-testid="handoff">{target.kind}:{target.objectID}:{target.archiveID ?? ''}</div> }));
function RouteProbe(): JSX.Element { return <div data-testid="route">{useLocation().pathname}</div>; }
function setup(): void { render(<QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}><MemoryRouter initialEntries={['/work']}><RouteProbe /><WorkspaceSearch /></MemoryRouter></QueryClientProvider>); }
function open(): void { act(() => window.dispatchEvent(new Event('whisper-workspace-search'))); }
beforeEach(() => {
  vi.clearAllMocks(); state.active = false; state.minimized = false;
  vi.stubGlobal('ResizeObserver', class { observe(): void {} unobserve(): void {} disconnect(): void {} });
  Element.prototype.scrollIntoView = vi.fn();
  const note = newNotebookDocument(state.owner); note.title = 'Private writing'; note.notes = 'Café proposal';
  vi.mocked(listNotebookDocuments).mockResolvedValue([note]);
  vi.mocked(fetchNotebookArchive).mockResolvedValue({ meetings: [{ id: 'meeting', title: 'Monday meeting', created_at: '2026-09-13', summary: 'Planning' } as WhisperMeeting], hasMore: false });
});
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });
describe('workspace command palette', () => {
  it('does not read the archive until explicitly opened and includes all five sources', async () => {
    setup(); expect(fetchNotebookArchive).not.toHaveBeenCalled(); open();
    await screen.findByText('Monday meeting'); await screen.findByText('Private writing'); await screen.findByText('Recorded planning'); await screen.findByText('Alex Person'); await screen.findByText('Delivery brief');
  });
  it('opens with Ctrl K, filters locally, and Enter on filters does not navigate', async () => {
    setup(); fireEvent.keyDown(window, { key: 'k', ctrlKey: true }); await screen.findByText('Monday meeting');
    const notes = screen.getByRole('button', { name: 'Notes' }); notes.focus(); fireEvent.keyDown(notes, { key: 'Enter' });
    expect(screen.getByTestId('route')).toHaveTextContent('/work'); expect(screen.getByRole('dialog')).toBeVisible();
    fireEvent.click(notes); expect(screen.queryByText('Monday meeting')).not.toBeInTheDocument();
    fireEvent.change(screen.getByRole('combobox', { name: 'Search workspace' }), { target: { value: 'cafe proposal' } });
    expect(screen.getByText('Private writing')).toBeVisible();
  });
  it('keeps earlier results after an older-page error and offers retry', async () => {
    vi.mocked(fetchNotebookArchive).mockResolvedValueOnce({ meetings: [{ id: 'meeting', title: 'Monday meeting', created_at: '2026-09-13' } as WhisperMeeting], hasMore: true }).mockRejectedValueOnce(new Error('offline'));
    setup(); open(); await screen.findByText('Monday meeting'); fireEvent.click(screen.getByRole('button', { name: 'Older meetings' }));
    await screen.findByText(/Meetings couldn’t load/); expect(screen.getByText('Monday meeting')).toBeVisible();
  });
  it('passes exact cloud backup identity to the object reader, without navigating away', async () => {
    setup(); open(); const button = await screen.findByRole('button', { name: 'Ask Jasper about this: Recorded planning' });
    button.focus(); fireEvent.keyDown(button, { key: 'Enter' }); expect(screen.getByTestId('route')).toHaveTextContent('/work');
    fireEvent.click(button); expect(await screen.findByTestId('handoff')).toHaveTextContent('Recordings:record:backup');
  });
  it('clears results on identity changes, including switching away and back before render', async () => {
    setup(); open(); await screen.findByText('Private writing');
    act(() => { state.auth?.('SIGNED_IN', { user: { id: 'different' } }); state.auth?.('SIGNED_IN', { user: { id: state.owner } }); });
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });
  it('ignores the global shortcut during the full-size call', async () => {
    state.active = true; setup(); fireEvent.keyDown(window, { key: 'k', metaKey: true });
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument()); expect(fetchNotebookArchive).not.toHaveBeenCalled();
  });
});
