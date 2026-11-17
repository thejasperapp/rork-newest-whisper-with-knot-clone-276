import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { toast } from 'sonner';
import { Link2 } from 'lucide-react';
import { askJasperMeetings, jasperMeetingRequest, type JasperAnswer } from '@/lib/jasperMeetings';
import { listNotebookDocuments } from '@/lib/notebookStorage';
import { fetchNotebookArchive } from '@/lib/notebookArchive';
import { Button } from './ui/button';
import { Input } from './ui/input';
import { Textarea } from './ui/textarea';

const schema = z.object({ title: z.string().trim().min(1).max(160), text: z.string().min(1).max(8000), meetings: z.array(z.string().uuid()).min(1).max(7) });
type Selection = z.infer<typeof schema>;

/** Explicit writing snapshot plus server-authorized meetings; never scans a whole private notebook. */
export function JasperNoteConnections({ owner, renderAnswer, initialNote }: { owner: string; renderAnswer: (answer: JasperAnswer) => ReactNode; initialNote?: { title: string; text: string } }): JSX.Element {
  const cache = useQueryClient();
  const form = useForm<Selection>({ resolver: zodResolver(schema), defaultValues: { title: initialNote?.title ?? 'My note excerpt', text: initialNote?.text ?? '', meetings: [] } });
  const [origin, setOrigin] = useState<{ id: string; revision: number } | null>(null);
  const [approved, setApproved] = useState<boolean>(false);
  const [reviewed, setReviewed] = useState<boolean>(false);
  const [answer, setAnswer] = useState<JasperAnswer | null>(null);
  const [saved, setSaved] = useState<boolean>(false);
  const [destination, setDestination] = useState<string>('');
  const [search, setSearch] = useState<string>('');
  const epoch = useRef<number>(0);
  const controller = useRef<AbortController | null>(null);
  const requestID = useRef<string | null>(null);
  const cancelRemote = useCallback((): void => {
    const id = requestID.current; requestID.current = null;
    if (id) void jasperMeetingRequest(owner, 'cancel', { id }).catch(() => toast.warning('Cancellation could not reach Jasper. Submitted work may finish; temporary results expire after 24 hours.'));
  }, [owner]);
  const notes = useQuery({ queryKey: ['personal-notebook', owner], queryFn: () => listNotebookDocuments(owner), networkMode: 'always' });
  const archive = useInfiniteQuery({ queryKey: ['jasper-connection-meetings', owner], initialPageParam: 0, queryFn: ({ pageParam, signal }) => fetchNotebookArchive(owner, pageParam, signal, true), getNextPageParam: (last, pages) => last.hasMore ? pages.length : undefined, gcTime: 0 });
  const meetings = [...new Map((archive.data?.pages.flatMap((p) => p.meetings) ?? []).map((m) => [m.id, m])).values()];
  const selected = form.watch('meetings');
  const invalidate = (): void => { epoch.current++; controller.current?.abort(); cancelRemote(); setApproved(false); setAnswer(null); setReviewed(false); setSaved(false); setDestination(''); };
  useEffect(() => () => { epoch.current++; controller.current?.abort(); cancelRemote(); }, [cancelRemote]);
  const checkOrigin = async (): Promise<void> => {
    if (!origin) return;
    const current = (await listNotebookDocuments(owner)).find((n) => n.id === origin.id);
    if (!current || current.revision !== origin.revision || current.notes !== form.getValues('text')) throw new Error('This saved note changed or was removed. Select it again and review the new snapshot.');
  };
  const ask = useMutation({ mutationFn: async (values: Selection) => {
    if (!approved) throw new Error('Approve this note and meeting selection first.');
    cancelRemote(); setAnswer(null); setReviewed(false); setSaved(false); setDestination('');
    const version = ++epoch.current;
    const abort = new AbortController(); controller.current = abort;
    await checkOrigin(); abort.signal.throwIfAborted();
    const id = crypto.randomUUID(); requestID.current = id;
    try {
    const result = await askJasperMeetings(owner, { requestId: id, question: 'Find useful connections between my note and these selected meetings. Highlight related decisions, possible links and things worth clarifying.', mode: 'connections', meetingIds: values.meetings, noteContext: { title: values.title, text: values.text }, consent: true }, abort.signal);
    await checkOrigin(); abort.signal.throwIfAborted();
    return { result, version };
    } catch (error) { if (requestID.current === id) cancelRemote(); throw error; }
  }, onSuccess: ({ result, version }) => { if (version === epoch.current) { setAnswer(result); setReviewed(false); setSaved(false); } } });
  const keep = useMutation({ mutationFn: async () => {
    if (ask.isPending || !answer || !reviewed || !destination) throw new Error('Review the connections and choose a meeting first.');
    const id = answer.id;
    const value = await jasperMeetingRequest<{ saved: boolean }>(owner, 'keep', { id, meetingId: destination });
    return { ...value, id };
  }, onSuccess: (value) => { if (value.saved && answer?.id === value.id) { requestID.current = null; setSaved(true); void cache.invalidateQueries({ queryKey: ['jasper-kept', owner] }); } } });
  const discard = useMutation({ mutationFn: () => jasperMeetingRequest(owner, 'clear', { ids: answer ? [answer.id] : [] }), onSuccess: () => { requestID.current = null; setAnswer(null); setReviewed(false); } });
  return <section aria-label="Note connections" className="space-y-4 rounded-2xl border bg-background p-4">
    <div><h3 className="flex items-center gap-2 text-sm font-semibold"><Link2 className="h-4 w-4" />Find connections</h3><p className="mt-2 text-xs leading-5 text-muted-foreground">Bring one note and choose up to seven meetings. Jasper highlights possible links, prior decisions and contradictions—not automatic facts or edits.</p></div>
    <form onSubmit={form.handleSubmit((values) => ask.mutate(values))} className="space-y-3">
      <fieldset disabled={keep.isPending || discard.isPending} className="space-y-3">
        <label className="block text-xs">Start from saved private writing<select className="mt-1 h-11 w-full rounded-xl border bg-background px-2" value={origin?.id ?? ''} onChange={(e) => { invalidate(); const note = notes.data?.find((n) => n.id === e.target.value); setOrigin(note ? { id: note.id, revision: note.revision } : null); if (note) { form.setValue('title', note.title || 'Untitled note'); form.setValue('text', note.notes); } }}><option value="">Paste or write an excerpt below</option>{notes.data?.filter((n) => n.notes.trim()).map((note) => <option key={note.id} value={note.id}>{note.title || 'Untitled note'}</option>)}</select></label>
        {notes.error && <p role="alert" className="text-xs">Saved writing could not load. <button type="button" className="min-h-11 underline" onClick={() => void notes.refetch()}>Retry writing</button></p>}
        <label className="block text-xs">Note title<Input maxLength={160} {...form.register('title', { onChange: invalidate })} /></label>
        <label className="block text-xs">Writing to analyze<Textarea className="mt-1 min-h-32" placeholder="Paste a note, idea or question you want to connect…" {...form.register('text', { onChange: () => { invalidate(); setOrigin(null); } })} /></label>
        <p className="text-xs text-muted-foreground">{form.watch('text').length.toLocaleString()} / 8,000 characters. Editing this excerpt does not edit your saved note.</p>
        <Input aria-label="Search connection meetings" placeholder="Search loaded meetings" value={search} onChange={(e) => setSearch(e.target.value)} />
        <div className="max-h-48 overflow-y-auto rounded-xl border px-3" aria-label="Meetings to compare">
          {meetings.filter((m) => m.title.toLocaleLowerCase().includes(search.toLocaleLowerCase()) || selected.includes(m.id)).map((m) => <label key={m.id} className="flex min-h-12 items-center gap-3 py-2 text-xs"><input type="checkbox" checked={selected.includes(m.id)} disabled={!selected.includes(m.id) && selected.length >= 7} onChange={() => { invalidate(); form.setValue('meetings', selected.includes(m.id) ? selected.filter((id) => id !== m.id) : [...selected, m.id]); }} /><span>{m.title}<span className="block text-muted-foreground">{new Date(m.created_at).toLocaleDateString()}</span></span></label>)}
          {!archive.isPending && !meetings.length && <p className="py-3 text-xs">No accessible saved meetings yet.</p>}
        </div>
        {archive.error && <Button type="button" variant="outline" onClick={() => void archive.refetch()}>Retry meetings</Button>}
        {archive.hasNextPage && <Button type="button" variant="ghost" disabled={archive.isFetchingNextPage} onClick={() => void archive.fetchNextPage()}>Older meetings</Button>}
        <label className="flex min-h-11 items-start gap-2 text-xs leading-5"><input className="mt-1" type="checkbox" checked={approved} onChange={(e) => { if (e.target.checked) setApproved(true); else invalidate(); }} /><span>Allow cloud AI to read this writing snapshot and these {selected.length} selected meetings. No other notes or recordings. Temporary answers expire after 24 hours unless kept; nothing is sent to attendees.</span></label>
        {Object.keys(form.formState.errors).length > 0 && <p role="alert" className="text-xs text-destructive">Choose 1–7 meetings and a nonempty note of up to 8,000 characters.</p>}
        <Button type="submit" className="min-h-11 rounded-full" disabled={!approved || !selected.length || ask.isPending}>{ask.isPending ? 'Looking for connections…' : 'Analyze selected context'}</Button>
        {ask.isPending && <Button type="button" variant="ghost" onClick={invalidate}>Stop</Button>}
      </fieldset>
    </form>
    {(ask.error || keep.error || discard.error) && <p role="alert" className="text-xs text-destructive">{(ask.error ?? keep.error ?? discard.error)?.message}</p>}
    {answer && <div className="space-y-3 border-t pt-4">{renderAnswer(answer)}{!answer.result.insufficient && <>
      <label className="flex min-h-11 items-center gap-2 text-xs"><input type="checkbox" checked={reviewed} disabled={keep.isPending || saved} onChange={(e) => setReviewed(e.target.checked)} />I’ve reviewed these suggested connections and quotes.</label>
      <select aria-label="Save connections with meeting" className="h-11 w-full rounded-xl border bg-background px-2 text-xs" value={destination} disabled={keep.isPending || saved} onChange={(e) => setDestination(e.target.value)}><option value="">Choose where to keep privately</option>{[...new Map(answer.sources.map((s) => [s.meetingId, s.meetingTitle])).entries()].map(([id, title]) => <option key={id} value={id}>{title}</option>)}</select>
      <Button disabled={ask.isPending || !reviewed || !destination || keep.isPending || saved} variant="outline" onClick={() => keep.mutate()}>{saved ? 'Connections kept privately' : 'Keep reviewed connections'}</Button>
    </>}{!saved && <Button variant="ghost" disabled={ask.isPending || keep.isPending || discard.isPending} onClick={() => discard.mutate()}>Dismiss connections</Button>}</div>}
  </section>;
}
