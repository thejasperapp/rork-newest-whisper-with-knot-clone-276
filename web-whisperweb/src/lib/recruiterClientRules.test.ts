import { describe, expect, it } from 'vitest';
import { emptyRecruiterClient, reviewedTeamCard, selectedMeetingIDs, updateRecruiterClient } from '../../../functions/recruiter-client-rules';
import { rankJasperPassages } from '../../../functions/jasper-ranked-evidence';
import { stageAge, clientMatches } from './recruiterClients';
import type { Prospect } from './recruiter';
const id = '10000000-0000-4000-8000-000000000001';
const p = { id, status: 'interested', updated_at: '2026-09-13T00:00:00Z' } as Prospect;
describe('private relationship contracts', () => {
  it('keeps stage history and clock unchanged on ordinary private edits', () => {
    const current = { ...emptyRecruiterClient('interested'), stageEnteredAt: '2026-09-01T00:00:00Z', stageHistory: [{ stage: 'interested', at: '2026-09-01T00:00:00Z' }] };
    const next = updateRecruiterClient(current, { revision: 0, email: 'someone@example.com', stage: 'ready', stageEnteredAt: '2026-09-13T00:00:00Z', publisherId: 'other' });
    expect(next.stage).toBe('interested'); expect(next.stageEnteredAt).toBe(current.stageEnteredAt); expect(next.stageHistory).toEqual(current.stageHistory);
    expect(stageAge(next, p.status, Date.parse('2026-09-13T00:00:00Z'))).toBe(12);
    expect(clientMatches('stalled', p, next, [], Date.parse('2026-09-13T00:00:00Z'))).toBe(true);
  });
  it('does not invent an age for untracked/legacy moves', () => { expect(stageAge(emptyRecruiterClient('interested'), 'interested')).toBeNull(); expect(stageAge({ ...emptyRecruiterClient('ready'), stageEnteredAt: '2026-09-01' }, 'meeting')).toBeNull(); });
  it('rejects stale revisions, invalid contacts and oversize text', () => {
    expect(() => updateRecruiterClient(emptyRecruiterClient(), { revision: 2 })).toThrow('revision_conflict');
    expect(() => updateRecruiterClient(emptyRecruiterClient(), { revision: 0, email: 'nope' })).toThrow();
    expect(() => updateRecruiterClient(emptyRecruiterClient(), { revision: 0, relationshipNotes: 'x'.repeat(4001) })).toThrow();
  });
  it('shares only reviewed allowlisted card fields', () => {
    const card = reviewedTeamCard({ name: 'Creator', role: 'creator', stage: 'interested', update: 'Arrange intro', confirm: true, email: 'private@example.com', phone: 'private', meetingIds: [id], relationshipNotes: 'secret', sources: ['secret'], publisherId: 'fake' }, id, id, 0);
    expect(Object.keys(card).sort()).toEqual(['id', 'publisherId', 'name', 'role', 'stage', 'update', 'publishedAt', 'revision'].sort()); expect(card.publisherId).toBe(id);
    expect(() => reviewedTeamCard({ name: 'Creator', role: 'creator', stage: 'interested', update: '', confirm: false }, id, id, 0)).toThrow('confirmation_required');
  });
  it('selected scope rejects empty, duplicate, malformed and over-eight IDs', () => {
    expect(selectedMeetingIDs([id])).toEqual([id]);
    for (const bad of [[], [id, id], ['not-an-id'], Array.from({ length: 9 }, (_, i) => `10000000-0000-4000-8000-${String(i).padStart(12, '0')}`)]) expect(() => selectedMeetingIDs(bad)).toThrow('invalid_meeting_scope');
  });
});
describe('ranked meeting evidence', () => {
  const row = (index: number, text: string) => ({ id: String(index), meeting_id: id, text, username: 'Alex', spoken_at: new Date(Date.UTC(2026, 8, 1, 12, index)).toISOString() });
  it('keeps short contexts chronological without requiring keyword overlap', () => {
    const ranked = rankJasperPassages([row(2, 'Friday works.'), row(1, 'I can send it then.')], 'What did we promise?', false);
    expect(ranked.excerpted).toBe(false); expect(ranked.rows.map((r) => r.id)).toEqual(['1', '2']);
  });
  it('prioritizes a late correction and its adjacent subject above repeated mentions', () => {
    const rows = Array.from({ length: 200 }, (_, i) => row(i, 'We promoted ten creators. '.repeat(8)));
    rows.push(row(201, 'For September, the previous number needs revision.'), row(202, 'Correction: it was six unique people, not ten.'), row(203, 'Two were coaches.'));
    const ranked = rankJasperPassages(rows, 'How many creators were promoted in September?', false);
    expect(ranked.excerpted).toBe(true); expect(ranked.rows.slice(0, 6).some((r) => r.id === '202')).toBe(true); expect(ranked.rows.slice(0, 6).some((r) => r.id === '201')).toBe(true);
  });
  it('retains exact offsets and never silently ranks scans', () => {
    const text = 'a'.repeat(1100) + 'correction: six';
    const ranked = rankJasperPassages([row(1, text)], 'six', true);
    expect(ranked.rows[1].offset).toBe(1100); expect(ranked.rows.map((r) => r.text).join('')).toBe(text);
  });
});
