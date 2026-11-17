import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { createMemoryRouter, RouterProvider } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { newNotebookDocument } from '@/lib/notebookDocument';
import { listNotebookDocuments } from '@/lib/notebookStorage';
import { fetchNotebookArchive } from '@/lib/notebookArchive';
import { fetchMeeting, type WhisperMeeting } from '@/lib/meetings';
import { loadJasperLibrary } from '@/lib/jasperMeetings';
import Notebook from './Notebook';
const auth = vi.hoisted(() => ({ id: '11d2d71c-f84a-4ab1-95bd-dd1a87a2c001', listeners: new Set<() => void>() }));
vi.mock('@/hooks/useAuth', async () => { const { useSyncExternalStore } = await import('react'); return { useAuth: () => { const id = useSyncExternalStore((listener) => { auth.listeners.add(listener); return () => { auth.listeners.delete(listener); }; }, () => auth.id); return { user: { id }, profile: null }; } }; });
vi.mock('@/lib/notebookArchive', () => ({ fetchNotebookArchive: vi.fn() }));
vi.mock('@/lib/notebookStorage', () => ({ listNotebookDocuments: vi.fn() }));
vi.mock('@/lib/meetings', () => ({ fetchMeeting: vi.fn(), fetchNotebookPrefs: async () => ({ prefs: {}, missing: false }), saveNotebookPref: vi.fn() }));
vi.mock('@/lib/jasperMeetings', async (original) => ({ ...await original<typeof import('@/lib/jasperMeetings')>(), loadJasperLibrary: vi.fn(), jasperMeetingRequest: vi.fn() }));
vi.mock('@/components/MeetingNotesScreen', () => ({ MeetingNotesScreen: ({ notes }: { notes: string }) => <section aria-label="Original meeting recap">{notes}</section> }));
vi.mock('@/components/JasperMeetingAssistant', () => ({ JasperMeetingAssistant: () => <section aria-label="Library sidekick">Ask across meetings</section> }));
vi.mock('@/components/MeetingRecordingLibrary', () => ({ MeetingRecordingLibrary: () => <section>Recordings</section> }));
vi.mock('@/components/NotebookRecordingSources', () => ({ NotebookRecordingSources: ({ note }: { note: { recordingIds?: string[] } }) => <section aria-label="Exact recording">{note.recordingIds?.[0]}</section> }));
const meetingA = '11d2d71c-f84a-4ab1-95bd-dd1a87a2c101', meetingB = '11d2d71c-f84a-4ab1-95bd-dd1a87a2c102';
function setup(path = `/notebook?meeting=${meetingA}`) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  const router = createMemoryRouter([{ path: '/notebook', element: <Notebook /> }], { initialEntries: [path] });
  render(<QueryClientProvider client={client}><RouterProvider router={router} /></QueryClientProvider>); return { router, client };
}
beforeEach(() => { vi.clearAllMocks(); auth.id = '11d2d71c-f84a-4ab1-95bd-dd1a87a2c001'; vi.mocked(loadJasperLibrary).mockResolvedValue({ revision: 0, folders: [{ id: 'creators', name: 'Creators' }, { id: 'coaches', name: 'Coaches' }, { id: 'team', name: 'Team' }], filings: { [meetingA]: 'creators' }, preferences: { focus: [], instructions: '' } }); vi.mocked(fetchNotebookArchive).mockResolvedValue({ meetings: [], hasMore: false }); vi.mocked(listNotebookDocuments).mockResolvedValue([]); vi.mocked(fetchMeeting).mockImplementation(async (id) => ({ id, title: 'Shared meeting', summary: 'Original recap evidence', status: 'ended', created_at: '2026-09-11T12:00:00Z' }) as WhisperMeeting); });
afterEach(cleanup);
describe('meeting library replaces Notebook UI without deleting its data', () => {
  it('shows folders and opens the original notes without importing private writing', async () => { setup(); await screen.findByRole('button', { name: 'Creators' }); expect(screen.queryByText('Notebook')).not.toBeInTheDocument(); fireEvent.click(await screen.findByRole('button', { name: 'Open note' })); expect(screen.getByRole('region', { name: 'Original meeting recap' })).toHaveTextContent('Original recap evidence'); expect(listNotebookDocuments).not.toHaveBeenCalled(); });
  it('filters folders while keeping unfiled meetings available in All meetings', async () => { vi.mocked(fetchNotebookArchive).mockResolvedValue({ meetings: [{ id: meetingA, title: 'Creator meeting', status: 'ended' }, { id: meetingB, title: 'Unfiled meeting', status: 'ended' }] as WhisperMeeting[], hasMore: false }); setup('/notebook'); await screen.findByText('Unfiled meeting'); fireEvent.click(await screen.findByRole('button', { name: 'Creators' })); expect(screen.queryByText('Unfiled meeting')).not.toBeInTheDocument(); expect(screen.getByText('Creator meeting')).toBeVisible(); fireEvent.click(screen.getByRole('button', { name: 'All meetings' })); expect(screen.getByText('Unfiled meeting')).toBeVisible(); });
  it('closes open snapshots when changing meeting scope', async () => { const { router } = setup(); fireEvent.click(await screen.findByRole('button', { name: 'Open note' })); await act(async () => router.navigate(`/notebook?meeting=${meetingB}`)); expect(screen.queryByRole('region', { name: 'Original meeting recap' })).not.toBeInTheDocument(); });
  it('clears open recaps across account switches', async () => { const { router } = setup(); fireEvent.click(await screen.findByRole('button', { name: 'Open note' })); await act(async () => { auth.id = crypto.randomUUID(); auth.listeners.forEach((listener) => listener()); await router.navigate(`/notebook?meeting=${meetingA}&changed=1`); }); expect(screen.queryByRole('region', { name: 'Original meeting recap' })).not.toBeInTheDocument(); });
  it('loads older transcript-only meetings without needing a summary', async () => { vi.mocked(fetchNotebookArchive).mockImplementation(async (_, page) => ({ meetings: [{ id: page ? meetingB : meetingA, title: page ? 'Older meeting' : 'Transcript only', summary: null, status: 'ended' } as WhisperMeeting], hasMore: !page })); setup('/notebook'); await screen.findByText('Transcript only'); fireEvent.click(screen.getByRole('button', { name: 'Load older meetings' })); await screen.findByText('Older meeting'); expect(listNotebookDocuments).not.toHaveBeenCalled(); });
  it('retains old note deep links as read-only writing, not the removed editor', async () => { const note = { ...newNotebookDocument(auth.id, meetingA, 'Earlier note'), notes: 'Keep my writing.' }; vi.mocked(listNotebookDocuments).mockResolvedValue([note]); const { router } = setup('/notebook'); await act(async () => router.navigate(`/notebook?note=${note.id}`)); await waitFor(() => expect(listNotebookDocuments).toHaveBeenCalled()); fireEvent.click(screen.getAllByText('Earlier private writing').find((element) => element.tagName === 'SUMMARY')!); expect(await screen.findByText('Keep my writing.')).toBeVisible(); expect(screen.queryByLabelText('My original notes')).not.toBeInTheDocument(); });
  it('reveals exact recording links during same-page navigation', async () => { const { router } = setup('/notebook'); await act(async () => router.navigate(`/notebook?meeting=${meetingA}&recording=${meetingB}`)); expect(await screen.findByRole('region', { name: 'Exact recording' })).toHaveTextContent(meetingB); });
  it('shows load failures rather than claiming no meetings exist', async () => { vi.mocked(fetchMeeting).mockRejectedValue(new Error('offline')); setup(); expect(await screen.findByRole('alert')).toHaveTextContent('Meeting history could not load'); expect(screen.queryByText('No meetings here yet')).not.toBeInTheDocument(); });
});
