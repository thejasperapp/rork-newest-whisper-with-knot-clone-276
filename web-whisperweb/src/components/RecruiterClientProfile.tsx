import { useEffect, useRef, useState } from 'react';
import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { LockKeyhole } from 'lucide-react';
import { toast } from 'sonner';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { JasperMeetingAnswerCard } from './JasperMeetingAssistant';
import { RecruiterPromotionRecords } from './RecruiterPromotionRecords';
import { RecruiterTeamPipeline } from './RecruiterTeamPipeline';
import { clientSchema, clientStageLabels, loadRecruiterClient, saveRecruiterClient, type RecruiterClient } from '@/lib/recruiterClients';
import { askJasperMeetings, jasperMeetingRequest, type JasperAnswer } from '@/lib/jasperMeetings';
import { fetchNotebookArchive } from '@/lib/notebookArchive';
import type { Prospect } from '@/lib/recruiter';

/** Private profile and selected meeting memory within the existing person drawer. */
export function RecruiterClientProfile({ owner, prospect }: { owner: string; prospect: Prospect }): JSX.Element {
  const query = useQuery({ queryKey: ['recruiter-client', owner, prospect.id], queryFn: ({ signal }) => loadRecruiterClient(owner, prospect.id, signal), gcTime: 0 });
  if (query.isError && !query.data) return <div role="alert" className="rounded-2xl border p-3 text-sm">{query.error.message}<Button variant="ghost" onClick={() => void query.refetch()}>Retry profile</Button></div>;
  if (!query.data) return <p className="text-sm text-muted-foreground">Loading private profile…</p>;
  return <ClientEditor key={`${owner}:${prospect.id}`} owner={owner} prospect={prospect} initial={query.data} />;
}
function ClientEditor({ owner, prospect, initial }: { owner: string; prospect: Prospect; initial: RecruiterClient }): JSX.Element {
  const cache = useQueryClient();
  const form = useForm<RecruiterClient>({ defaultValues: initial, resolver: zodResolver(clientSchema) });
  const [question, setQuestion] = useState<string>('');
  const [approvedScope, setApprovedScope] = useState<string>('');
  const [answer, setAnswer] = useState<JasperAnswer | null>(null);
  const [search, setSearch] = useState<string>('');
  const [showMeetings, setShowMeetings] = useState<boolean>(false);
  const memory = useRef<HTMLDivElement | null>(null);
  const controller = useRef<AbortController | null>(null);
  const evidenceEpoch = useRef<number>(0);
  const invalidateEvidence = (): void => { evidenceEpoch.current++; controller.current?.abort(); setAnswer(null); setApprovedScope(''); };
  useEffect(() => { if (!form.formState.isDirty && initial.revision !== form.getValues('revision')) form.reset(initial); }, [initial, form]);
  useEffect(() => () => controller.current?.abort(), []);
  const selected = form.watch('meetingIds');
  const scopeKey = [...selected].sort().join(',');
  const archive = useInfiniteQuery({ queryKey: ['client-meeting-picker', owner], enabled: showMeetings, initialPageParam: 0, queryFn: ({ pageParam, signal }) => fetchNotebookArchive(owner, pageParam, signal, true), getNextPageParam: (last, pages) => last.hasMore ? pages.length : undefined, gcTime: 0 });
  const meetings = [...new Map((archive.data?.pages.flatMap((page) => page.meetings) ?? []).map((m) => [m.id, m])).values()];
  const save = useMutation({ mutationFn: (values: RecruiterClient) => saveRecruiterClient(owner, prospect.id, values), onSuccess: (client) => { form.reset(client); void cache.invalidateQueries({ queryKey: ['recruiter-clients', owner] }); void cache.invalidateQueries({ queryKey: ['recruiter-client', owner, prospect.id] }); toast.success('Saved privately to your account.'); } });
  const ask = useMutation({ mutationFn: async (text: string) => {
    if (!selected.length || approvedScope !== scopeKey) throw new Error('Choose meetings and approve this scope first.');
    controller.current?.abort(); controller.current = new AbortController();
    const name = prospect.prospect_display_name || prospect.prospect_username || 'this creator or coach';
    const epoch = evidenceEpoch.current;
    // Relationship answers stay meeting-grounded: no general-knowledge items can be mistaken for something the person said.
    const value = await askJasperMeetings(owner, { question: `About ${name.slice(0, 140)}: ${text}`.slice(0, 600), meetingIds: [...selected], mode: 'ask', knowledge: false, consent: true }, controller.current.signal);
    return { value, epoch };
  }, onSuccess: ({ value, epoch }) => { if (epoch === evidenceEpoch.current) setAnswer(value); } });
  const reload = useMutation({ mutationFn: () => { invalidateEvidence(); return loadRecruiterClient(owner, prospect.id); }, onSuccess: (client) => { form.reset(client); setApprovedScope(''); setAnswer(null); save.reset(); } });
  const keep = useMutation({ mutationFn: () => jasperMeetingRequest(owner, 'keep', { id: answer?.id, meetingId: answer?.sources[0]?.meetingId }), onSuccess: () => toast.success('Kept privately with the first cited meeting.') });
  const ready = selected.length > 0 && approvedScope === scopeKey && !ask.isPending;
  const changeMeetings = (id: string): void => { if (save.isPending) return; form.setValue('meetingIds', selected.includes(id) ? selected.filter((v) => v !== id) : [...selected, id], { shouldDirty: true }); invalidateEvidence(); };
  return <fieldset disabled={save.isPending || reload.isPending} className="min-w-0 space-y-4 rounded-[20px] border bg-card p-4">
    <div><h3 className="flex items-center gap-2 font-semibold"><LockKeyhole className="h-4 w-4" /> Private relationship</h3><p className="mt-1 text-xs text-muted-foreground">Your relationship notebook for this creator or coach: contact preferences, follow-ups and the meetings you choose. People keeps the details; Pipeline tracks progress. Only you can see this—team cards are separate, reviewed snapshots.</p></div>
    <Button type="button" variant="outline" className="min-h-11" onClick={() => { memory.current?.scrollIntoView({ block: 'start' }); memory.current?.querySelector('textarea')?.focus({ preventScroll: true }); }}>Ask Jasper about this</Button>
    <form onSubmit={form.handleSubmit((values) => save.mutate(values))} className="space-y-3">
      <fieldset disabled={save.isPending} className="space-y-3">
        <label className="block text-xs">Email<Input type="email" autoComplete="off" maxLength={254} {...form.register('email')} /></label>
        <label className="block text-xs">Phone<Input type="tel" autoComplete="off" maxLength={60} {...form.register('phone')} /></label>
        <label className="block text-xs">Contact preferences<Textarea maxLength={1200} placeholder="Best channel, time zone, things to remember" {...form.register('preferences')} /></label>
        <label className="block text-xs">Relationship notes<Textarea maxLength={4000} {...form.register('relationshipNotes')} /></label>
        <label className="block text-xs">Next follow-up<Input maxLength={600} {...form.register('followUp')} /></label>
        <label className="block text-xs">Follow-up due<Input type="date" {...form.register('followUpDue')} /></label>
        <label className="block text-xs">Next meeting (your local time)<Input type="datetime-local" value={form.watch('nextMeetingAt') ? localDateTime(form.watch('nextMeetingAt')) : ''} onChange={(e) => form.setValue('nextMeetingAt', e.target.value ? new Date(e.target.value).toISOString() : '', { shouldDirty: true })} /></label>
      </fieldset>
      {Object.keys(form.formState.errors).length > 0 && <p role="alert" className="text-xs text-destructive">Check field lengths, email and dates.</p>}
      {save.error && <div role="alert" className="text-xs text-destructive">{save.error.message} Your draft is still here.<Button type="button" variant="ghost" disabled={reload.isPending} onClick={() => { if (window.confirm('Discard this unsaved draft and reload the saved profile?')) reload.mutate(); }}>Reload saved profile</Button></div>}
      <Button type="submit" disabled={save.isPending}>{save.isPending ? 'Saving…' : 'Save private profile'}</Button>
    </form>
    <details className="text-xs"><summary className="cursor-pointer py-2">Stage history</summary>{initial.stageHistory.length ? initial.stageHistory.map((item) => <p key={`${item.at}:${item.stage}`} className="py-1">{clientStageLabels[item.stage] ?? item.stage} · {new Date(item.at).toLocaleString()}</p>) : <p>Earlier stage-entry dates weren’t recorded. New stage moves are tracked separately from edits.</p>}</details>
    <div ref={memory} className="space-y-3 border-t pt-4">
      <h3 className="font-semibold">Meeting memory</h3>
      <RecruiterPromotionRecords owner={owner} />
      <p className="text-xs text-muted-foreground">Select up to eight meetings you can access. This does not attach recordings or grant anyone access.</p>
      <Button variant="outline" onClick={() => setShowMeetings((v) => !v)}>Choose linked meetings · {selected.length}/8</Button>
      {selected.map((id) => <div key={id} className="flex items-center gap-2 text-xs"><a className="min-w-0 flex-1 truncate underline" href={`/notebook?meeting=${id}`} target="_blank" rel="noreferrer">{meetings.find((m) => m.id === id)?.title ?? `Linked meeting ${selected.indexOf(id) + 1}`}</a><Button variant="ghost" size="sm" onClick={() => changeMeetings(id)}>Unlink</Button></div>)}
      {showMeetings && <div className="space-y-2 rounded-xl bg-muted/40 p-2"><Input aria-label="Find meeting" placeholder="Search loaded meetings" value={search} onChange={(e) => setSearch(e.target.value)} />{meetings.filter((m) => m.title.toLowerCase().includes(search.toLowerCase())).map((m) => <label key={m.id} className="flex min-h-11 items-center gap-2 text-xs"><input type="checkbox" checked={selected.includes(m.id)} disabled={!selected.includes(m.id) && selected.length >= 8} onChange={() => changeMeetings(m.id)} /><span>{m.title}<span className="block text-muted-foreground">{new Date(m.created_at).toLocaleDateString()}</span></span></label>)}{archive.error && <p role="alert">Couldn’t load meetings. <button onClick={() => void archive.refetch()}>Retry</button></p>}{archive.hasNextPage && <Button variant="ghost" disabled={archive.isFetching} onClick={() => void archive.fetchNextPage()}>Older meetings</Button>}</div>}
      <p className="text-xs text-muted-foreground">Save your profile to keep these links. Only selected saved speech and original meeting notes go to Jasper; long transcripts use labeled excerpts.</p>
      <label className="flex min-h-11 items-start gap-2 text-xs"><input className="mt-1" type="checkbox" checked={!!scopeKey && approvedScope === scopeKey} onChange={(e) => { if (e.target.checked) setApprovedScope(scopeKey); else invalidateEvidence(); }} /><span>Allow cloud AI for these {selected.length} selected meetings. My private contact fields are not sent.</span></label>
      <div className="flex flex-wrap gap-2">{['Before-meeting refresher', 'What did we promise them?', 'Suggest follow-ups and profile updates'].map((text) => <Button key={text} variant="outline" size="sm" disabled={!ready} onClick={() => ask.mutate(text)}>{text}</Button>)}</div>
      <Textarea aria-label="Ask about this client" placeholder="Ask about this relationship…" maxLength={420} value={question} onChange={(e) => setQuestion(e.target.value)} />
      <Button disabled={!ready || !question.trim()} onClick={() => ask.mutate(question)}>{ask.isPending ? 'Reading selected evidence…' : 'Ask Jasper'}</Button>
      {ask.error && <p role="alert" className="text-xs text-destructive">{ask.error.message}</p>}
      {answer && <div className="space-y-3"><JasperMeetingAnswerCard answer={answer} /><p className="text-xs text-muted-foreground">Review suggestions below. They only fill your draft; nothing changes until you save.</p>{answer.result.actions.map((action, i) => <Button className="h-auto min-h-11 whitespace-normal text-left" variant="outline" key={i} onClick={() => { form.setValue('followUp', action.title, { shouldDirty: true }); toast.info(`Review follow-up and choose a due date. Suggested timing: ${action.when || 'not specified'}`); }}>Review follow-up: {action.title}</Button>)}{answer.result.sections.flatMap((section) => section.items).map((item, i) => <Button className="h-auto min-h-11 whitespace-normal text-left" variant="ghost" key={i} onClick={() => form.setValue('relationshipNotes', `${form.getValues('relationshipNotes')}\n${item.text}\nSource: ${item.sourceIds.map((id) => { const s = answer.sources.find((v) => v.id === id); return s ? `${s.meetingTitle} (${s.spokenAt})` : ''; }).join('; ')}`.trim(), { shouldDirty: true })}>Review note: {item.text}</Button>)}{answer.sources.length > 0 && <Button variant="outline" disabled={keep.isPending} onClick={() => keep.mutate()}>Keep answer with first cited meeting</Button>}{keep.error && <p role="alert">{keep.error.message}</p>}</div>}
    </div>
    <RecruiterTeamPipeline owner={owner} prospect={prospect} />
  </fieldset>;
}
function localDateTime(value: string): string { const date = new Date(value); return new Date(date.getTime() - date.getTimezoneOffset() * 60000).toISOString().slice(0, 16); }
