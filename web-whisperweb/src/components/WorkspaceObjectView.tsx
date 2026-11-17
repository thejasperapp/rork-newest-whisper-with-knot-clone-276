import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { supabase } from '@/lib/supabase';
import { listNotebookDocuments } from '@/lib/notebookStorage';
import { listRecordings } from '@/lib/meetingRecordingStorage';
import { listRecordingArchivePage, recordingArchiveSchema } from '@/lib/recordingCloud';
import { workLink, workRequest, type WorkScope, type WorkView } from '@/lib/workspace';
import type { Prospect } from '@/lib/recruiter';
import type { WhisperMeeting } from '@/lib/meetings';
import type { WorkspaceSearchResult } from '@/lib/workspaceSearch';
import { Button } from './ui/button';
import { JasperMeetingAssistant, JasperMeetingAnswerCard } from './JasperMeetingAssistant';
import { JasperNoteConnections } from './JasperNoteConnections';
import { NotebookQuestions } from './NotebookQuestions';
import { RecruiterClientProfile } from './RecruiterClientProfile';
import { CloudRecordingPlayer } from './CloudRecordingLibrary';
import { RecordingPlayer } from './MeetingRecordingLibrary';

export type WorkspaceObjectTarget = Pick<WorkspaceSearchResult, 'kind' | 'objectID'> & { scope?: WorkScope; ask?: boolean; archiveID?: string; revision?: number };
/** Resolves an exact selected identity again before exposing its existing assistant. No auto-send. */
export function WorkspaceObjectView({ owner, target, close }: { owner: string; target: WorkspaceObjectTarget; close: () => void }): JSX.Element {
  const query = useQuery({ queryKey: ['workspace-selected-object', owner, target.kind, target.objectID, target.archiveID, target.revision, target.scope?.space, target.scope?.team], gcTime: 0, retry: false, queryFn: async ({ signal }) => {
    const { data: session } = await supabase.auth.getSession(); signal.throwIfAborted();
    if (session.session?.user.id !== owner) throw new Error('Account changed. Reopen this item.');
    const id = target.objectID;
    if (target.kind === 'Notes') {
      const note = (await listNotebookDocuments(owner)).find((n) => n.id === id && n.ownerId === owner && !n.deletedAt); signal.throwIfAborted();
      if (!note) throw new Error('This private note is no longer available on this device.');
      return { kind: 'note' as const, note };
    }
    if (target.kind === 'Meetings') {
      const [meeting, membership] = await Promise.all([
        supabase.from('whisper_meetings').select('*').eq('id', id).limit(1).abortSignal(signal),
        supabase.from('whisper_meeting_participants').select('meeting_id').eq('meeting_id', id).eq('user_id', owner).limit(1).abortSignal(signal),
      ]);
      signal.throwIfAborted();
      const row = meeting.data?.[0] as WhisperMeeting | undefined;
      if (meeting.error || membership.error || !row || (row.host_id !== owner && !membership.data?.length)) throw new Error('This meeting is no longer available to this account.');
      return { kind: 'meeting' as const, meeting: row };
    }
    if (target.kind === 'People') {
      const { data, error } = await supabase.from('whisper_recruiter_prospects').select('*').eq('recruiter_id', owner).eq('id', id).limit(1).abortSignal(signal);
      signal.throwIfAborted(); if (error || !data?.[0]) throw new Error('This person is no longer in your private People list.');
      return { kind: 'person' as const, person: data[0] as Prospect };
    }
    if (target.kind === 'Recordings') {
      if (target.archiveID) {
        const { data, error } = await supabase.from('whisper_recording_archives').select('*').eq('id', target.archiveID).eq('owner_id', owner).eq('recording_id', id).limit(1).abortSignal(signal);
        signal.throwIfAborted(); const parsed = recordingArchiveSchema.safeParse(data?.[0]);
        if (error || !parsed.success || (target.revision !== undefined && parsed.data.source_revision !== target.revision)) throw new Error('This recording snapshot changed or is no longer available. Reopen search.');
        return { kind: 'cloudRecording' as const, archive: parsed.data };
      }
      const local = (await listRecordings(owner)).find((r) => r.ownerId === owner && r.id === id && r.status !== 'recording'); signal.throwIfAborted();
      if (local) {
        if (target.revision !== undefined && target.revision !== local.revision) throw new Error('This recording changed. Reopen search for its current transcript.');
        return { kind: 'localRecording' as const, record: local };
      }
      if (target.revision !== undefined) throw new Error('The selected local recording is unavailable. Choose a cloud backup separately.');
      const page = await listRecordingArchivePage(owner, signal, undefined, null, id);
      const archive = page.items.find((r) => r.recording_id === id && r.owner_id === owner);
      if (!archive) throw new Error('This recording is no longer available.');
      return { kind: 'cloudRecording' as const, archive };
    }
    if (!target.scope) throw new Error('Open this item from its work board.');
    const item = await workRequest<WorkView>(owner, target.scope, `/item/${id}`, undefined, signal);
    return { kind: 'work' as const, item };
  } });
  if (query.isError) return <div role="alert" className="space-y-3"><p>{query.error.message}</p><Button onClick={() => void query.refetch()}>Retry access</Button></div>;
  const value = query.data;
  if (!value) return <p role="status">Opening selected item…</p>;
  switch (value.kind) {
    case 'note': return <section className="space-y-4"><h3 className="text-xl font-semibold">{value.note.title || 'Untitled note'}</h3><Button asChild variant="outline"><Link onClick={close} to={`/notebook?portal=workspace&note=${value.note.id}`}>Open original writing</Link></Button><NotebookQuestions ownerId={owner} documents={[value.note]} onDocumentSaved={() => void query.refetch()} /></section>;
    case 'meeting': return <section className="space-y-4"><h3 className="text-xl font-semibold">{value.meeting.title}</h3><Button asChild variant="outline"><Link onClick={close} to={`/notebook?portal=workspace&meeting=${value.meeting.id}`}>Open original notes & recordings</Link></Button><JasperMeetingAssistant owner={owner} meetingID={value.meeting.id} embedded /></section>;
    case 'person': return <section className="space-y-4"><h3 className="text-xl font-semibold">{value.person.prospect_display_name || value.person.prospect_username || 'Private relationship'}</h3><p className="text-xs text-muted-foreground">Ask Jasper in Meeting memory below. Choose the evidence first; private contact fields are not sent.</p><RecruiterClientProfile owner={owner} prospect={value.person} /></section>;
    case 'localRecording': return <section className="space-y-4"><p className="text-xs text-muted-foreground">Choose the permitted transcript passages below to ask Jasper. No audio is sent by opening playback.</p><RecordingPlayer record={value.record} onClose={close} embedded /></section>;
    case 'cloudRecording': return <section className="space-y-4"><p className="text-xs text-muted-foreground">Choose the permitted transcript passages below to ask Jasper. No audio is sent by opening playback.</p><CloudRecordingPlayer archive={value.archive} onClose={close} embedded /></section>;
    case 'work': return <section className="space-y-4"><h3 className="text-xl font-semibold">{value.item.title}</h3><p className="whitespace-pre-wrap text-sm">{value.item.brief}</p><Button asChild variant="outline"><Link onClick={close} to={new URL(workLink(target.scope!, value.item.id)).pathname + new URL(workLink(target.scope!, value.item.id)).search}>Open work item</Link></Button>{value.item.external ? <p className="text-sm text-muted-foreground">This is a shared publication. Private workspace context is not available here.</p> : <><p className="text-xs text-muted-foreground">Selected brief · revision {value.item.revision}. Choose meetings to find cited connections. Internal notes and discussions are excluded.</p><JasperNoteConnections key={value.item.revision} owner={owner} initialNote={{ title: value.item.title, text: value.item.brief }} renderAnswer={(answer) => <JasperMeetingAnswerCard answer={answer} />} /></>}</section>;
  }
}
