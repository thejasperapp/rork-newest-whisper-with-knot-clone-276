import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { JasperNoteConnections } from './JasperNoteConnections';
import { JasperMeetingAnswerCard } from './JasperMeetingAssistant';
import { askJasperMeetings, jasperMeetingRequest, type JasperAnswer } from '@/lib/jasperMeetings';
import { listNotebookDocuments } from '@/lib/notebookStorage';
import { fetchNotebookArchive } from '@/lib/notebookArchive';
import { newNotebookDocument } from '@/lib/notebookDocument';
vi.mock('@/lib/notebookStorage', () => ({ listNotebookDocuments: vi.fn() }));
vi.mock('@/lib/notebookArchive', () => ({ fetchNotebookArchive: vi.fn() }));
vi.mock('@/lib/jasperMeetings', () => ({ askJasperMeetings: vi.fn(), jasperMeetingRequest: vi.fn(), loadJasperLibrary: vi.fn() }));
const owner = '10000000-0000-4000-8000-000000000001', meeting = '10000000-0000-4000-8000-000000000002';
const note = { ...newNotebookDocument(owner), title: 'Pilot ideas', notes: 'Try a smaller pilot.', revision: 2 };
const answer: JasperAnswer = { id: '10000000-0000-4000-8000-000000000003', question: 'Find connections', generatedAt: '2026-09-13', scope: 'Note + 1 meeting', coverage: 'Selected context', meetingId: null, noteContext: { title: note.title, text: note.notes }, sources: [{ id: 'S1', meetingId: meeting, meetingTitle: 'Pilot review', segmentId: meeting, spokenAt: '2026-09-01', speaker: 'Alex', text: 'Ten teams in the pilot.', offset: 0 }], result: { insufficient: false, sections: [{ title: 'Possible connections', items: [{ text: 'The pilot idea relates to the ten-team limit.', sourceIds: ['S1'], noteQuote: 'smaller pilot' }] }], actions: [] } };
function setup() { const cache = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } }); return render(<QueryClientProvider client={cache}><JasperNoteConnections owner={owner} renderAnswer={(value) => <JasperMeetingAnswerCard answer={value} />} /></QueryClientProvider>); }
async function select() { await screen.findByRole('option', { name: 'Pilot ideas' }); fireEvent.change(screen.getByLabelText('Start from saved private writing'), { target: { value: note.id } }); fireEvent.click(screen.getByLabelText(/Pilot review/)); }
function approve() { fireEvent.click(screen.getByLabelText(/Allow cloud AI/)); }
beforeEach(() => { vi.clearAllMocks(); vi.mocked(listNotebookDocuments).mockResolvedValue([note]); vi.mocked(fetchNotebookArchive).mockResolvedValue({ meetings: [{ id: meeting, title: 'Pilot review', host_id: owner, status: 'ended', created_at: '2026-09-01' }], hasMore: false } as Awaited<ReturnType<typeof fetchNotebookArchive>>); vi.mocked(askJasperMeetings).mockResolvedValue(answer); vi.mocked(jasperMeetingRequest).mockResolvedValue({ saved: true }); });
afterEach(cleanup);
describe('explicit note connection review', () => {
  it('sends only the selected writing and meetings after consent; keeps only after review', async () => {
    setup(); await select(); expect(askJasperMeetings).not.toHaveBeenCalled(); expect(screen.getByRole('button', { name: 'Analyze selected context' })).toBeDisabled(); approve(); fireEvent.click(screen.getByRole('button', { name: 'Analyze selected context' }));
    await screen.findByText('The pilot idea relates to the ten-team limit.');
    expect(vi.mocked(askJasperMeetings).mock.calls[0][1]).toMatchObject({ mode: 'connections', meetingIds: [meeting], noteContext: { title: 'Pilot ideas', text: note.notes }, consent: true });
    expect(screen.getByText('smaller pilot').tagName).toBe('MARK'); expect(jasperMeetingRequest).not.toHaveBeenCalled();
    expect(screen.getByRole('button', { name: 'Keep reviewed connections' })).toBeDisabled();
    fireEvent.click(screen.getByLabelText(/I’ve reviewed/)); fireEvent.change(screen.getByLabelText('Save connections with meeting'), { target: { value: meeting } }); fireEvent.click(screen.getByRole('button', { name: 'Keep reviewed connections' }));
    await screen.findByText('Connections kept privately'); expect(jasperMeetingRequest).toHaveBeenCalledWith(owner, 'keep', { id: answer.id, meetingId: meeting });
  });
  it('invalidates approval when writing or selected meetings change', async () => {
    setup(); await select(); approve(); fireEvent.change(screen.getByLabelText('Writing to analyze'), { target: { value: 'Different writing' } }); expect(screen.getByLabelText(/Allow cloud AI/)).not.toBeChecked(); approve(); fireEvent.click(screen.getByLabelText(/Pilot review/)); expect(screen.getByLabelText(/Allow cloud AI/)).not.toBeChecked(); expect(askJasperMeetings).not.toHaveBeenCalled();
  });
  it('discards a late transport result after consent withdrawal', async () => {
    let finish: ((value: JasperAnswer) => void) | undefined;
    vi.mocked(askJasperMeetings).mockImplementation(() => new Promise((resolve) => { finish = resolve; }));
    setup(); await select(); approve(); fireEvent.click(screen.getByRole('button', { name: 'Analyze selected context' })); await waitFor(() => expect(askJasperMeetings).toHaveBeenCalledOnce()); approve(); await act(async () => finish?.(answer)); expect(screen.queryByText('The pilot idea relates to the ten-team limit.')).not.toBeInTheDocument();
  });
  it('refuses to analyze a saved note that was deleted since selection', async () => {
    setup(); await select(); vi.mocked(listNotebookDocuments).mockResolvedValue([]); approve(); fireEvent.click(screen.getByRole('button', { name: 'Analyze selected context' })); expect(await screen.findByRole('alert')).toHaveTextContent('changed or was removed'); expect(askJasperMeetings).not.toHaveBeenCalled(); expect(screen.getByLabelText('Writing to analyze')).toHaveValue(note.notes);
  });
  it('presents related findings separately and avoids claiming global absence for a no-match', () => {
    render(<JasperMeetingAnswerCard answer={{ ...answer, noteContext: undefined, result: { ...answer.result, related: true } }} />); expect(screen.getByText(/didn’t find an exact answer/)).toBeVisible(); cleanup();
    render(<JasperMeetingAnswerCard answer={{ ...answer, result: { insufficient: true, sections: [], actions: [] } }} />); expect(screen.getByText(/doesn’t mean it was never discussed/)).toBeVisible(); expect(screen.queryByText(/but I found/)).not.toBeInTheDocument();
  });
});
