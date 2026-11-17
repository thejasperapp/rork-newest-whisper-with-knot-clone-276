import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { RecruiterClientProfile } from './RecruiterClientProfile';
import { RecruiterTeamPipeline } from './RecruiterTeamPipeline';
import { loadRecruiterClient, saveRecruiterClient, type RecruiterClient } from '@/lib/recruiterClients';
import { askJasperMeetings, jasperMeetingRequest, type JasperAnswer } from '@/lib/jasperMeetings';
import { emptyRecruiterClient } from '../../../functions/recruiter-client-rules';
import type { Prospect } from '@/lib/recruiter';
vi.mock('@/lib/recruiterClients', async (original) => ({ ...await original<typeof import('@/lib/recruiterClients')>(), loadRecruiterClient: vi.fn(), saveRecruiterClient: vi.fn() }));
vi.mock('@/lib/jasperMeetings', async (original) => ({ ...await original<typeof import('@/lib/jasperMeetings')>(), askJasperMeetings: vi.fn(), jasperMeetingRequest: vi.fn() }));
vi.mock('./RecruiterPromotionRecords', () => ({ RecruiterPromotionRecords: () => <div>Recorded totals are separate</div> }));
vi.mock('@/lib/notebookArchive', () => ({ fetchNotebookArchive: vi.fn(async () => ({ meetings: [], hasMore: false })) }));
const owner = '10000000-0000-4000-8000-000000000001', id = '10000000-0000-4000-8000-000000000002', meeting = '10000000-0000-4000-8000-000000000003', business = '10000000-0000-4000-8000-000000000004';
const profile: RecruiterClient = { ...emptyRecruiterClient('interested'), email: 'private@example.com', relationshipNotes: 'Private original note', meetingIds: [meeting] };
const prospect = { id, recruiter_id: owner, prospect_display_name: 'Sam', suggested_role: 'creator', status: 'interested', notes: 'Private prospect note' } as Prospect;
const answer: JasperAnswer = { id, generatedAt: '2026-09-13T12:00:00Z', question: 'Promises?', scope: 'One selected meeting', coverage: 'Ranked excerpts only', partialEvidence: true, meetingId: null, sources: [{ id: 'S1', meetingId: meeting, meetingTitle: 'Creator intro', segmentId: id, spokenAt: '2026-09-01T12:00:00Z', speaker: 'Sam', text: 'Send the draft Friday.', offset: 0 }], result: { insufficient: false, sections: [{ title: 'Answer', items: [{ text: 'Sam asked for a draft.', sourceIds: ['S1'] }] }], actions: [{ title: 'Send the draft', owner: 'Recruiter', when: 'Friday', sourceIds: ['S1'] }] } };
function mount(team = false) {
  const cache = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  render(<QueryClientProvider client={cache}>{team ? <RecruiterTeamPipeline owner={owner} prospect={prospect} /> : <RecruiterClientProfile owner={owner} prospect={prospect} />}</QueryClientProvider>);
  return cache;
}
beforeEach(() => {
  vi.clearAllMocks(); vi.mocked(loadRecruiterClient).mockResolvedValue(structuredClone(profile)); vi.mocked(saveRecruiterClient).mockImplementation(async (_owner, _id, client) => ({ ...client, revision: client.revision + 1 })); vi.mocked(askJasperMeetings).mockResolvedValue(answer);
  vi.mocked(jasperMeetingRequest).mockImplementation(async (_owner, path) => path === 'clients/teams' ? { teams: [{ id: business, name: 'Our team' }] } : path.startsWith('clients/team?') ? { cards: [], revisions: {} } : { saved: true });
});
afterEach(cleanup);
describe('reviewed private meeting memory', () => {
  it('requires selected-scope consent and never sends private contact fields', async () => {
    mount(); await screen.findByDisplayValue('private@example.com');
    expect(screen.getByRole('button', { name: 'What did we promise them?' })).toBeDisabled(); expect(askJasperMeetings).not.toHaveBeenCalled();
    fireEvent.click(screen.getByLabelText(/Allow cloud AI for these/)); fireEvent.click(screen.getByRole('button', { name: 'What did we promise them?' }));
    await screen.findByText('Sam asked for a draft.'); const input = vi.mocked(askJasperMeetings).mock.calls[0][1];
    expect(input.meetingIds).toEqual([meeting]); expect(input.meetingId).toBeUndefined(); expect(input.folderId).toBeUndefined(); expect(JSON.stringify(input)).not.toContain('private@example.com'); expect(JSON.stringify(input)).not.toContain('Private original note');
    expect(screen.getByText(/Partial evidence ·/)).toBeVisible(); expect(saveRecruiterClient).not.toHaveBeenCalled();
  });
  it('only changes a review draft until Save, preserves original notes and exposes citations', async () => {
    mount(); await screen.findByDisplayValue('private@example.com'); fireEvent.click(screen.getByLabelText(/Allow cloud AI for these/)); fireEvent.click(screen.getByRole('button', { name: 'What did we promise them?' }));
    await screen.findByRole('button', { name: 'Review follow-up: Send the draft' }); fireEvent.click(screen.getByRole('button', { name: 'Review follow-up: Send the draft' }));
    expect(screen.getByLabelText('Next follow-up')).toHaveValue('Send the draft'); expect(saveRecruiterClient).not.toHaveBeenCalled(); expect(screen.getByLabelText('Relationship notes')).toHaveValue('Private original note');
    fireEvent.click(screen.getAllByText('1 source · inspect quotes')[0]); expect(screen.getAllByRole('link', { name: 'Open original meeting notes' })[0]).toHaveAttribute('href', `/notebook?meeting=${meeting}`);
    fireEvent.click(screen.getByRole('button', { name: 'Save private profile' })); await waitFor(() => expect(saveRecruiterClient).toHaveBeenCalledTimes(1));
    expect(vi.mocked(saveRecruiterClient).mock.calls[0][2].followUp).toBe('Send the draft');
  });
  it('discards a late result after consent withdrawal even if the transport ignores abort', async () => {
    let resolve: (value: JasperAnswer) => void = () => undefined;
    vi.mocked(askJasperMeetings).mockReturnValue(new Promise((done) => { resolve = done; }));
    mount(); await screen.findByDisplayValue('private@example.com'); fireEvent.click(screen.getByLabelText(/Allow cloud AI for these/)); fireEvent.click(screen.getByRole('button', { name: 'What did we promise them?' }));
    await waitFor(() => expect(askJasperMeetings).toHaveBeenCalledTimes(1)); fireEvent.click(screen.getByLabelText(/Allow cloud AI for these/));
    await act(async () => { resolve(answer); }); expect(screen.queryByText('Sam asked for a draft.')).not.toBeInTheDocument(); expect(screen.queryByRole('button', { name: 'Review follow-up: Send the draft' })).not.toBeInTheDocument();
  });
  it('keeps a rejected save draft instead of claiming success or resetting it', async () => {
    vi.mocked(saveRecruiterClient).mockRejectedValue(new Error('Revision changed. Reload.')); mount(); await screen.findByDisplayValue('private@example.com');
    fireEvent.change(screen.getByLabelText('Relationship notes'), { target: { value: 'Unsaved but retained' } }); fireEvent.click(screen.getByRole('button', { name: 'Save private profile' }));
    await screen.findByText(/Revision changed/); expect(screen.getByLabelText('Relationship notes')).toHaveValue('Unsaved but retained');
  });
});
describe('explicit team card review', () => {
  it('publishes only the preview and requires a new review when its revision changes', async () => {
    const cache = mount(true); await screen.findByRole('option', { name: 'Our team' }); fireEvent.change(screen.getByLabelText('Team pipeline'), { target: { value: business } });
    await screen.findByLabelText('Team update'); expect(screen.getByRole('button', { name: 'Publish reviewed card' })).toBeDisabled();
    fireEvent.change(screen.getByLabelText('Team update'), { target: { value: 'Team-safe update' } }); fireEvent.click(screen.getByLabelText('I reviewed this exact card for the selected team.'));
    await act(async () => { cache.setQueryData(['client-team-cards', owner, business], { cards: [], revisions: { [id]: 2 } }); });
    await waitFor(() => expect(screen.getByRole('button', { name: 'Publish reviewed card' })).toBeDisabled()); fireEvent.click(screen.getByLabelText('I reviewed this exact card for the selected team.')); fireEvent.click(screen.getByRole('button', { name: 'Publish reviewed card' }));
    await waitFor(() => expect(vi.mocked(jasperMeetingRequest).mock.calls.some((c) => c[2] !== undefined)).toBe(true));
    const body = vi.mocked(jasperMeetingRequest).mock.calls.find((c) => c[2] !== undefined)?.[2]; expect(body).toEqual({ id, name: 'Sam', role: 'creator', stage: 'interested', update: 'Team-safe update', revision: 2, confirm: true }); expect(JSON.stringify(body)).not.toContain('Private');
  });
});
