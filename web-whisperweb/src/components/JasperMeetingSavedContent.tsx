import { useQuery } from '@tanstack/react-query';
import { z } from 'zod';
import { listNotebookDocuments } from '@/lib/notebookStorage';
import { listNotebookRecoveries } from '@/lib/notebookRecovery';
import { jasperAnswerSchema, jasperMeetingRequest } from '@/lib/jasperMeetings';
import { JasperMeetingAnswerCard } from './JasperMeetingAssistant';
import { WorkspaceAskButton } from './WorkspaceAskButton';
import { Button } from './ui/button';

/** Preserves earlier private writing without recreating the removed notebook workspace. */
export function JasperEarlierWriting({ owner, meetingID, noteID }: { owner: string; meetingID?: string; noteID?: string }): JSX.Element {
  const query = useQuery({ queryKey: ['personal-notebook', owner], queryFn: () => listNotebookDocuments(owner), networkMode: 'always' });
  const recoveries = useQuery({ queryKey: ['jasper-earlier-recovery', owner], queryFn: () => listNotebookRecoveries(owner), networkMode: 'always' });
  const docs = (query.data ?? []).filter((note) => (!meetingID || note.meetingId === meetingID) && (!noteID || note.id === noteID));
  const exportAll = (): void => { const blob = new Blob([JSON.stringify({ writing: docs, recoveries: recoveries.data ?? [] }, null, 2)], { type: 'application/json' }); const url = URL.createObjectURL(blob); const anchor = document.createElement('a'); anchor.href = url; anchor.download = 'whisper-earlier-writing.json'; anchor.click(); setTimeout(() => URL.revokeObjectURL(url), 1000); };
  return <details className="rounded-2xl border border-border p-4 text-foreground"><summary className="min-h-11 cursor-pointer py-3 text-sm font-medium">Earlier private writing</summary><p className="my-3 text-xs text-muted-foreground">Your previous writing and recovery data are retained. This does not replace the original meeting notes.</p>{query.error && <p role="alert">Earlier writing could not load. Please retry.</p>}{docs.map((note) => <article key={note.id} className="my-4 border-t border-border pt-3"><h3 className="font-medium">{note.title || 'Untitled'}</h3><WorkspaceAskButton target={{ kind: 'Notes', objectID: note.id }} /><p className="mt-2 whitespace-pre-wrap text-sm leading-6">{note.notes}</p>{note.transcript && <details><summary className="min-h-11 py-3 text-xs">Stored transcript excerpt</summary><p className="whitespace-pre-wrap text-sm">{note.transcript}</p></details>}{note.enhancement && <details><summary className="min-h-11 py-3 text-xs">Earlier Jasper result</summary>{note.enhancement.sections.map((section) => <section key={section.title}><h4 className="font-medium">{section.title}</h4>{section.items.map((item) => <p key={item.text} className="my-2 text-sm">{item.text}</p>)}</section>)}</details>}</article>)}<Button variant="outline" className="h-11 text-xs" onClick={exportAll} disabled={query.isPending || query.isError || recoveries.isError}>Export writing & recovery data</Button></details>;
}
export function JasperMeetingSavedContent({ owner, meetingID }: { owner: string; meetingID: string }): JSX.Element {
  const query = useQuery({ queryKey: ['jasper-kept', owner, meetingID], queryFn: async ({ signal }) => z.object({ answers: z.array(jasperAnswerSchema) }).parse(await jasperMeetingRequest(owner, `history?meetingId=${encodeURIComponent(meetingID)}`, undefined, signal)) });
  return <section className="space-y-4 text-foreground">{query.data?.answers.map((answer) => <details key={answer.id} className="rounded-2xl border border-border bg-card p-4"><summary className="min-h-11 cursor-pointer py-3 text-sm font-semibold">Private Jasper notes · {new Date(answer.generatedAt).toLocaleDateString()}</summary><JasperMeetingAnswerCard answer={answer} /></details>)}{query.error && <p className="text-xs text-muted-foreground">Private Jasper additions could not load. <button className="min-h-11 underline" onClick={() => void query.refetch()}>Retry</button></p>}<JasperEarlierWriting owner={owner} meetingID={meetingID} /></section>;
}
