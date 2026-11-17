import { describe, expect, it } from 'vitest';
import { defaultJasperLibrary, updateJasperLibrary, jasperSearchTerms, jasperRetrievalTerms, jasperRecordingEvidence, validateJasperResult, type JasperEvidence } from '../../../functions/jasper-meeting-rules';
const meeting = '00000000-0000-4000-8000-000000000001';
describe('private meeting organization and grounded answer contracts', () => {
  it('keeps folders private and removes filing metadata without deleting any meeting', () => { const filed = updateJasperLibrary(defaultJasperLibrary(), { revision: 0, action: 'file', meetingId: meeting, folderId: 'creators' }); expect(filed.filings[meeting]).toBe('creators'); const removed = updateJasperLibrary(filed, { revision: 1, action: 'folder.remove', id: 'creators' }); expect(removed.filings).toEqual({}); expect(removed.folders.map((folder) => folder.id)).toEqual(['coaches', 'team']); });
  it('refuses stale organization writes', () => { const current = { ...defaultJasperLibrary(), revision: 3 }; expect(() => updateJasperLibrary(current, { revision: 2, action: 'folder.remove', id: 'team' })).toThrow('revision_conflict'); expect(current.folders).toHaveLength(3); });
  it('does not undo over a later filing, even with the latest revision', () => {
    const filed = updateJasperLibrary(defaultJasperLibrary(), { revision: 0, action: 'file', meetingId: meeting, folderId: 'team' });
    expect(() => updateJasperLibrary(filed, { revision: 1, action: 'file', meetingId: meeting, folderId: null, expectedFolder: 'creators' })).toThrow('revision_conflict');
  });
  it('rejects invalid folders and excessive preferences', () => { expect(() => updateJasperLibrary(defaultJasperLibrary(), { revision: 0, action: 'file', meetingId: meeting, folderId: 'someone-elses-folder' })).toThrow('invalid_folder'); expect(() => updateJasperLibrary(defaultJasperLibrary(), { revision: 0, action: 'preferences', focus: Array(13).fill('priority'), instructions: '' })).toThrow('invalid_preferences'); });
  it('extracts names and subject words without query operators', () => { expect(jasperSearchTerms('How many clients did Josh have last month?')).toEqual(['clients', 'josh']); expect(jasperSearchTerms('Josh),text.neq.secret')).not.toContain('),'); });
  it('reads current meeting context without requiring the question to occur in its transcript', () => {
    for (const question of ['What did I miss?', 'Generate notes', 'What decisions were made?', 'What is the deadline?', 'What was agreed?', 'What did we decide?']) expect(jasperRetrievalTerms(question, true, false)).toEqual([]);
    expect(jasperRetrievalTerms('What did Josh say?', true, false)).toEqual([]);
    expect(jasperRetrievalTerms('How many clients did Josh have?', true, false)).toEqual([]);
    expect(jasperRetrievalTerms('Summarize my recent meetings', false, false)).toEqual([]);
    expect(jasperRetrievalTerms('How many clients did Josh have last month?', false, false)).toEqual(['clients', 'josh']);
  });
  it('keeps selected private recording evidence distinct with its real media position', () => {
    const source = jasperRecordingEvidence({ id: meeting, title: 'Private', revision: 2, passages: [{ id: 'A1-0', start: 32.5, end: 39, text: 'We agreed to ship Friday.', timing: 'speech' }] }, meeting, 'Weekly', '2026-09-13');
    expect(source[0]).toMatchObject({ kind: 'recording', recordingId: meeting, position: 32.5, revision: 2, text: 'We agreed to ship Friday.' });
    expect(source[0].speaker).toContain('not identified');
    expect(() => jasperRecordingEvidence({ id: meeting, title: 'Private', revision: 1, passages: [{ id: 'x', start: -3, end: 1, text: 'no', timing: 'speech' }] }, meeting, 'Weekly', '')).toThrow();
  });
  it('retains supplied speaker labels without asserting verified identity', () => {
    const source = jasperRecordingEvidence({ id: meeting, title: 'Recording', revision: 1, passages: [{ id: 'S1', start: 2, end: 4, text: 'Agreed.', timing: 'speech', speakerName: 'Alex' }] }, meeting, 'Weekly', '2026-09-13');
    expect(source[0].speaker).toBe('Alex · supplied recording source label');
  });
  it('rejects recording context overflow instead of silently trimming it', () => {
    expect(() => jasperRecordingEvidence({ id: meeting, title: 'Private', revision: 1, passages: Array.from({ length: 3 }, (_, i) => ({ id: String(i), start: i, end: i + 1, text: 'a'.repeat(10000), timing: 'chunk' })) }, meeting, 'Weekly', '')).toThrow('transcript_too_long');
  });
  it('rejects fabricated citation IDs and unsupported empty results', () => { const sources: JasperEvidence[] = [{ id: 'S1', meetingId: meeting, meetingTitle: 'Weekly', segmentId: meeting, spokenAt: '2026-09-01', speaker: 'Josh', text: '24 clients in August', offset: 0 }]; expect(() => validateJasperResult({ insufficient: false, sections: [{ title: 'Answer', items: [{ text: '24 clients', sourceIds: ['fake'] }] }], actions: [] }, sources)).toThrow('invalid_answer'); expect(() => validateJasperResult({ insufficient: true, sections: [], actions: [] }, sources)).not.toThrow(); });
});
