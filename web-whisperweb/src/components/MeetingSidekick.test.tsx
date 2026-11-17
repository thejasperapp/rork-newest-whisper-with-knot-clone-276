import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { MeetingSidekick } from './MeetingSidekick';
import { JasperMeetingAssistant } from './JasperMeetingAssistant';
import { sidekickTranscript, type SidekickSpeech } from '@/lib/meetingSidekick';
import { askJasperMeetings, jasperMeetingRequest, loadJasperLibrary, type JasperAnswer } from '@/lib/jasperMeetings';
vi.mock('@/lib/meetingSidekick', async (original) => ({ ...await original<typeof import('@/lib/meetingSidekick')>(), sidekickTranscript: vi.fn() }));
vi.mock('@/lib/jasperMeetings', () => ({ askJasperMeetings: vi.fn(), jasperMeetingRequest: vi.fn(), loadJasperLibrary: vi.fn() }));
const owner = '00000000-0000-4000-8000-000000000001', meetingID = '00000000-0000-4000-8000-000000000002';
const speech: SidekickSpeech = { id: '00000000-0000-4000-8000-000000000003', meeting_id: meetingID, text: 'Josh reported 24 clients in August.', username: 'Alex', spoken_at: '2026-09-02T12:00:00Z' };
const result: JasperAnswer = { id: '00000000-0000-4000-8000-000000000004', question: 'How many clients?', generatedAt: '2026-09-13T12:00:00Z', meetingId: meetingID, scope: 'All my meetings', coverage: 'Searched matching excerpts, not an exhaustive count.', sources: [{ id: 'S1', meetingId: meetingID, meetingTitle: 'Creator weekly', segmentId: speech.id, spokenAt: speech.spoken_at, speaker: 'Alex', text: speech.text, offset: 0 }], result: { insufficient: false, sections: [{ title: 'Answer', items: [{ text: 'Josh reported 24 clients for August.', sourceIds: ['S1'] }] }], actions: [] } };
function setup() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  const hide = vi.fn(), retry = vi.fn();
  const view = (visible = true) => <QueryClientProvider client={client}><MeetingSidekick owner={owner} meetingID={meetingID} title="Creator weekly" visible={visible} captureStatus="Transcribing your microphone" interim="Private provisional words" onHide={hide} onRetryCapture={retry} /></QueryClientProvider>;
  const rendered = render(view());
  fireEvent.click(screen.getByRole('button', { name: /^Transcript/ }));
  return { ...rendered, client, view, hide, retry };
}
beforeEach(() => { vi.clearAllMocks(); vi.mocked(sidekickTranscript).mockResolvedValue({ rows: [speech], complete: true }); vi.mocked(loadJasperLibrary).mockResolvedValue({ revision: 0, folders: [{ id: 'creators', name: 'Creators' }], filings: {}, preferences: { focus: [], instructions: '' } }); vi.mocked(askJasperMeetings).mockResolvedValue(result); vi.mocked(jasperMeetingRequest).mockResolvedValue({ saved: true }); });
afterEach(cleanup);
describe('meeting-first Jasper sidekick', () => {
  it('opens saved transcript in one tap, without opening a notebook or copying a note', async () => { setup(); expect(await screen.findByText(speech.text)).toBeVisible(); expect(screen.queryByRole('button', { name: 'Open meeting notepad' })).not.toBeInTheDocument(); expect(screen.getByText('Private provisional words')).toBeVisible(); expect(askJasperMeetings).not.toHaveBeenCalled(); });
  it('keeps a typed question when hidden and never starts capture just by viewing transcript', async () => { const app = setup(); await screen.findByText(speech.text); fireEvent.change(screen.getByLabelText('Ask Jasper about meetings'), { target: { value: 'Remember my question' } }); app.rerender(app.view(false)); app.rerender(app.view(true)); expect(screen.getByLabelText('Ask Jasper about meetings')).toHaveValue('Remember my question'); expect(app.retry).not.toHaveBeenCalled(); });
  it('searches all meetings only after explicit consent and sends no provisional speech', async () => { setup(); await screen.findByText(speech.text); fireEvent.change(screen.getByLabelText('Search meeting scope'), { target: { value: 'all' } }); fireEvent.change(screen.getByLabelText('Ask Jasper about meetings'), { target: { value: 'How many clients?' } }); fireEvent.click(screen.getByRole('button', { name: 'Send Jasper question' })); expect(askJasperMeetings).not.toHaveBeenCalled(); fireEvent.click(screen.getByRole('button', { name: 'Continue with Jasper' })); await screen.findByText('Josh reported 24 clients for August.'); expect(vi.mocked(askJasperMeetings).mock.calls[0][1]).toEqual({ question: 'How many clients?', mode: 'ask', consent: true, meetingId: undefined, folderId: undefined }); expect(JSON.stringify(vi.mocked(askJasperMeetings).mock.calls)).not.toContain('Private provisional'); });
  it('exposes the dated source and keeps an answer with the original meeting only on request', async () => { setup(); fireEvent.change(screen.getByLabelText('Ask Jasper about meetings'), { target: { value: 'How many clients?' } }); fireEvent.click(screen.getByRole('button', { name: 'Send Jasper question' })); fireEvent.click(screen.getByRole('button', { name: 'Continue with Jasper' })); await screen.findByText('Josh reported 24 clients for August.'); expect(jasperMeetingRequest).not.toHaveBeenCalled(); fireEvent.click(screen.getByText('1 source · inspect quotes')); expect(screen.getByRole('link', { name: 'Open original meeting notes' })).toHaveAttribute('href', `/notebook?meeting=${meetingID}`); fireEvent.click(screen.getByRole('button', { name: 'Keep with meeting notes' })); await screen.findByText('Saved with meeting'); expect(jasperMeetingRequest).toHaveBeenCalledWith(owner, 'keep', { id: result.id, meetingId: meetingID }); });
  it('keeps the initial composer uncluttered and remembers consent only for the approved scope', async () => {
    vi.mocked(askJasperMeetings).mockResolvedValueOnce(result).mockResolvedValueOnce({ ...result, id: crypto.randomUUID() });
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(<QueryClientProvider client={client}><MeetingSidekick owner={owner} meetingID={meetingID} title="Weekly" visible captureStatus="Listening" interim="" onHide={vi.fn()} onRetryCapture={vi.fn()} /></QueryClientProvider>);
    expect(screen.getByRole('button', { name: /^Transcript/ })).toHaveAttribute('aria-expanded', 'false');
    fireEvent.click(screen.getByRole('button', { name: 'What did I miss?' })); expect(askJasperMeetings).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', { name: 'Continue with Jasper' })); await screen.findByText('Josh reported 24 clients for August.');
    fireEvent.change(screen.getByLabelText('Ask Jasper about meetings'), { target: { value: 'Next steps?' } }); fireEvent.keyDown(screen.getByLabelText('Ask Jasper about meetings'), { key: 'Enter' });
    await waitFor(() => expect(askJasperMeetings).toHaveBeenCalledTimes(2));
    await waitFor(() => expect(screen.getByLabelText('Search meeting scope')).not.toBeDisabled());
    fireEvent.change(screen.getByLabelText('Search meeting scope'), { target: { value: 'all' } }); fireEvent.change(screen.getByLabelText('Ask Jasper about meetings'), { target: { value: 'Compare all' } }); fireEvent.click(screen.getByRole('button', { name: 'Send Jasper question' }));
    expect(screen.getByRole('region', { name: 'Approve Jasper search' })).toBeVisible(); expect(askJasperMeetings).toHaveBeenCalledTimes(2);
  });
  it('sends only explicitly selected recording context after approval without broadening the scope', async () => {
    const context = { id: crypto.randomUUID(), title: 'Private recording', revision: 3, passages: [{ id: 'A1-0', start: 32, end: 35, text: 'Selected private recording passage.', timing: 'speech' as const }] };
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(<QueryClientProvider client={client}><JasperMeetingAssistant owner={owner} meetingID={meetingID} recordingContext={context} /></QueryClientProvider>);
    expect(screen.queryByLabelText('Search meeting scope')).not.toBeInTheDocument();
    fireEvent.change(screen.getByLabelText('Ask Jasper about meetings'), { target: { value: 'What was agreed?' } });
    fireEvent.click(screen.getByRole('button', { name: 'Send Jasper question' })); expect(askJasperMeetings).not.toHaveBeenCalled();
    expect(screen.getByText(/Only your selected private recording passages/)).toBeVisible();
    fireEvent.click(screen.getByRole('button', { name: 'Continue with Jasper' }));
    await waitFor(() => expect(askJasperMeetings).toHaveBeenCalledOnce());
    expect(vi.mocked(askJasperMeetings).mock.calls[0][1]).toMatchObject({ meetingId: meetingID, consent: true, recordingContext: context });
  });
  it('shows read failures rather than waiting for nonexistent speech and exposes both retries', async () => { vi.mocked(sidekickTranscript).mockRejectedValue(new Error('Saved speech is delayed.')); const app = setup(); expect(await screen.findByRole('alert')).toHaveTextContent('Saved speech is delayed.'); expect(screen.queryByText(/No saved speech yet/)).not.toBeInTheDocument(); fireEvent.click(screen.getByRole('button', { name: 'Retry capture' })); expect(app.retry).toHaveBeenCalledOnce(); fireEvent.click(screen.getByRole('button', { name: 'Refresh transcript' })); await waitFor(() => expect(sidekickTranscript).toHaveBeenCalledTimes(2)); });
  it('discloses a partial visible window without pretending it is a full transcript', async () => { vi.mocked(sidekickTranscript).mockResolvedValue({ rows: [speech], complete: false }); setup(); expect(await screen.findByText(/Showing the latest 200 passages/)).toBeVisible(); });
  it('labels general knowledge, offers follow-ups and a Jasper Intelligence handoff without inventing meeting evidence', async () => {
    const knowledge: JasperAnswer = { ...result, id: '00000000-0000-4000-8000-000000000005', question: 'What is a retainer agreement?', sources: [], coverage: 'No matching excerpts were found.', result: { insufficient: false, grounding: 'knowledge', followups: ['How do I price a retainer?'], sections: [{ title: "From Jasper's knowledge", items: [{ kind: 'knowledge', text: 'A retainer is a recurring fee paid in advance for ongoing availability or work.', sourceIds: [] }] }], actions: [] } };
    vi.mocked(askJasperMeetings).mockResolvedValueOnce(knowledge).mockResolvedValueOnce({ ...knowledge, id: '00000000-0000-4000-8000-000000000006', question: 'How do I price a retainer?' });
    setup(); await screen.findByText(speech.text);
    fireEvent.change(screen.getByLabelText('Ask Jasper about meetings'), { target: { value: 'What is a retainer agreement?' } }); fireEvent.click(screen.getByRole('button', { name: 'Send Jasper question' }));
    expect(screen.getByText(/Jasper may also answer general questions from its own knowledge/)).toBeVisible(); fireEvent.click(screen.getByRole('button', { name: 'Continue with Jasper' }));
    await screen.findByText(/A retainer is a recurring fee/); expect(screen.getByText('Jasper’s knowledge · not from your meetings')).toBeVisible(); expect(screen.getByText(/not said in your meetings · verify important facts/)).toBeVisible(); expect(screen.queryByText(/source · inspect quotes/)).not.toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Continue in Jasper Intelligence' })).toHaveAttribute('href', `/ember?q=${encodeURIComponent('What is a retainer agreement?')}`);
    fireEvent.click(screen.getByRole('button', { name: 'How do I price a retainer?' }));
    await waitFor(() => expect(askJasperMeetings).toHaveBeenCalledTimes(2)); expect(vi.mocked(askJasperMeetings).mock.calls[1][1]).toMatchObject({ question: 'How do I price a retainer?', mode: 'ask', meetingId: meetingID });
  });
  it('opens recipes with a slash, runs the chosen recipe through the same scope approval, and never sends the slash text', async () => {
    setup(); await screen.findByText(speech.text);
    fireEvent.change(screen.getByLabelText('Ask Jasper about meetings'), { target: { value: '/sound' } });
    const tray = screen.getByRole('region', { name: 'Sidekick recipes' }); expect(tray).toBeVisible(); expect(screen.queryByText('Recap next steps')).not.toBeInTheDocument(); expect(screen.getByRole('button', { name: 'Send Jasper question' })).toBeDisabled();
    fireEvent.keyDown(screen.getByLabelText('Ask Jasper about meetings'), { key: 'Enter' }); expect(askJasperMeetings).not.toHaveBeenCalled();
    expect(screen.getByRole('region', { name: 'Approve Jasper search' })).toBeVisible(); fireEvent.click(screen.getByRole('button', { name: 'Continue with Jasper' }));
    await waitFor(() => expect(askJasperMeetings).toHaveBeenCalledOnce()); expect(vi.mocked(askJasperMeetings).mock.calls[0][1]).toMatchObject({ question: expect.stringContaining('Suggest two concise, thoughtful contributions'), mode: 'ask', meetingId: meetingID }); expect(JSON.stringify(vi.mocked(askJasperMeetings).mock.calls)).not.toContain('/sound');
    fireEvent.click(screen.getByRole('button', { name: 'Sidekick recipes' })); expect(screen.getByRole('region', { name: 'Sidekick recipes' })).toBeVisible(); expect(screen.getByText('Organize transcript')).toBeVisible();
  });
  it('shows scanning only while an approved scan runs, then highlights the cited passage', async () => { let finish: ((answer: JasperAnswer) => void) | undefined; vi.mocked(askJasperMeetings).mockImplementation(() => new Promise((resolve) => { finish = resolve; })); setup(); await screen.findByText(speech.text); expect(screen.queryByLabelText('Scanning transcript')).not.toBeInTheDocument(); fireEvent.click(screen.getByText('More with Jasper')); fireEvent.click(screen.getByRole('button', { name: 'Scan & organize transcript' })); expect(askJasperMeetings).not.toHaveBeenCalled(); fireEvent.click(screen.getByRole('button', { name: 'Continue with Jasper' })); await waitFor(() => expect(askJasperMeetings).toHaveBeenCalledOnce()); expect(screen.getByLabelText('Scanning transcript')).toBeVisible(); fireEvent.change(screen.getByLabelText('Ask Jasper about meetings'), { target: { value: 'Next question' } }); await act(async () => finish?.(result)); expect(screen.queryByLabelText('Scanning transcript')).not.toBeInTheDocument(); expect(screen.getByLabelText('Ask Jasper about meetings')).toHaveValue('Next question'); });
});
