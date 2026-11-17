import type { WhisperMeeting } from './meetings';
import type { NotebookDocument } from './notebookDocument';
import type { MeetingRecording } from './meetingRecordingModel';
import type { RecordingArchive } from './recordingCloud';
import type { Prospect } from './recruiter';
import type { WorkSummary } from './workspace';

export const workspaceSearchKinds = ['All', 'Meetings', 'Notes', 'Recordings', 'People', 'Work'] as const;
export type WorkspaceSearchKind = typeof workspaceSearchKinds[number];
/** Identity and searchable text only; selection is never permission to send to AI. */
export type WorkspaceSearchResult = { id: string; objectID: string; kind: Exclude<WorkspaceSearchKind, 'All'>; title: string; text: string; date: string; archiveID?: string; revision?: number };
export function workspaceSearchResults(owner: string, meetings: WhisperMeeting[], notes: NotebookDocument[], recordings: MeetingRecording[], people: Prospect[], work: WorkSummary[], archives: RecordingArchive[] = []): WorkspaceSearchResult[] {
  const rows: WorkspaceSearchResult[] = [
    ...meetings.map((m): WorkspaceSearchResult => ({ id: `Meetings:${m.id}`, objectID: m.id, kind: 'Meetings', title: m.title || 'Meeting', text: m.summary ?? '', date: m.created_at ?? '' })),
    ...notes.filter((n) => n.ownerId === owner && !n.deletedAt).map((n): WorkspaceSearchResult => ({ id: `Notes:${n.id}`, objectID: n.id, kind: 'Notes', title: n.title || 'Untitled note', text: `${n.notes} ${n.transcript} ${n.people}`, date: n.updatedAt })),
    ...recordings.filter((r) => r.ownerId === owner && r.status !== 'recording').map((r): WorkspaceSearchResult => ({ id: `Recordings:local:${r.id}`, objectID: r.id, kind: 'Recordings', title: r.title || 'Recording', text: r.transcript.map((p) => p.text).join(' '), date: r.createdAt, revision: r.revision })),
    ...archives.filter((a) => a.owner_id === owner && a.snapshot.ownerId === owner).map((a): WorkspaceSearchResult => ({ id: `Recordings:cloud:${a.id}`, objectID: a.recording_id, archiveID: a.id, revision: a.source_revision, kind: 'Recordings', title: a.snapshot.title || 'Recording', text: a.snapshot.transcript.map((p) => p.text).join(' '), date: a.created_at })),
    ...people.filter((p) => p.recruiter_id === owner).map((p): WorkspaceSearchResult => ({ id: `People:${p.id}`, objectID: p.id, kind: 'People', title: p.prospect_display_name || p.prospect_username || 'Person', text: [p.prospect_username, p.niche, p.suggested_role, p.status].filter(Boolean).join(' '), date: p.updated_at ?? '' })),
    ...work.map((w): WorkspaceSearchResult => ({ id: `Work:${w.id}`, objectID: w.id, kind: 'Work', title: w.title, text: `${w.kind} ${w.status} ${w.deadline}`, date: w.updatedAt })),
  ];
  return [...new Map(rows.map((r) => [r.id, r])).values()].sort((a, b) => b.date.localeCompare(a.date) || a.id.localeCompare(b.id));
}
/** Diacritic-insensitive, AND-token matching; literal search, never a query language. */
export function matchWorkspaceResults(rows: WorkspaceSearchResult[], query: string, kind: WorkspaceSearchKind): WorkspaceSearchResult[] {
  const normalize = (text: string): string => text.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLocaleLowerCase();
  const terms = normalize(query).trim().split(/\s+/).filter(Boolean);
  return rows.filter((r) => (kind === 'All' || r.kind === kind) && terms.every((term) => normalize(`${r.title} ${r.text}`).includes(term)));
}
