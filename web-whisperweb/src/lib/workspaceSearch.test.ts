import { describe, expect, it } from 'vitest';
import { newNotebookDocument } from './notebookDocument';
import { matchWorkspaceResults, workspaceSearchResults, type WorkspaceSearchResult } from './workspaceSearch';
import type { RecordingArchive } from './recordingCloud';
import type { MeetingRecording } from './meetingRecordingModel';

const owner = '00000000-0000-4000-8000-000000000001';
describe('workspace search boundaries', () => {
  it('excludes deleted and other-account private writing', () => {
    const mine = newNotebookDocument(owner); mine.notes = 'selected truth';
    const deleted = { ...newNotebookDocument(owner), deletedAt: '2026-09-14T00:00:00Z' };
    const other = newNotebookDocument('00000000-0000-4000-8000-000000000002');
    expect(workspaceSearchResults(owner, [], [mine, deleted, other], [], [], []).map((r) => r.objectID)).toEqual([mine.id]);
  });
  it('uses all query tokens, accents, type filters, and literal punctuation', () => {
    const rows: WorkspaceSearchResult[] = [{ id: 'Notes:1', objectID: '1', kind: 'Notes', title: 'Café weekly', text: 'Budget (final)', date: '' }, { id: 'Work:1', objectID: '1', kind: 'Work', title: 'Café weekly', text: 'Unapproved', date: '' }];
    expect(matchWorkspaceResults(rows, 'CAFE final', 'All')).toHaveLength(1);
    expect(matchWorkspaceResults(rows, 'cafe', 'Work')[0].id).toBe('Work:1');
    expect(matchWorkspaceResults(rows, '.*', 'All')).toHaveLength(0);
    expect(matchWorkspaceResults(rows, ' ', 'All')).toHaveLength(2);
  });
  it('keeps recording backups and local revisions as distinct exact identities', () => {
    const record = { id: 'record', ownerId: owner, status: 'ready', title: 'Weekly', createdAt: '2026-09-14', revision: 3, transcript: [{ text: 'Local latest' }] } as MeetingRecording;
    const archive = (id: string, revision: number, text: string): RecordingArchive => ({ id, owner_id: owner, recording_id: record.id, source_revision: revision, snapshot: { ...record, revision, transcript: [{ id: 'p', start: 0, end: 1, timing: 'speech', text }] }, created_at: '2026-09-13', state: 'ready', media_bytes: 44, audio_bytes: 44 });
    const rows = workspaceSearchResults(owner, [], [], [record], [], [], [archive('new', 2, 'Newer quote'), archive('old', 1, 'Older quote')]);
    expect(rows).toHaveLength(3);
    const older = matchWorkspaceResults(rows, 'Older quote', 'Recordings')[0];
    expect(older.archiveID).toBe('old'); expect(older.revision).toBe(1);
    expect(matchWorkspaceResults(rows, 'Local latest', 'Recordings')[0].archiveID).toBeUndefined();
  });
  it('does not collapse objects sharing an id across types or mutate source data', () => {
    const note = newNotebookDocument(owner); const before = structuredClone(note);
    const rows = workspaceSearchResults(owner, [], [note, note], [], [], []);
    expect(rows).toHaveLength(1); expect(note).toEqual(before);
  });
});
