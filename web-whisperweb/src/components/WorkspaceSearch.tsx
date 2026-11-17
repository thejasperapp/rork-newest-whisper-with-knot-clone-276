import { useEffect, useMemo, useRef, useState } from 'react';
import { useInfiniteQuery, useQuery } from '@tanstack/react-query';
import { useLocation, useNavigate } from 'react-router-dom';
import { ArrowLeft, FileText, Sparkles } from 'lucide-react';
import { useAuth } from '@/hooks/useAuth';
import { useMeetingHost } from '@/hooks/useMeetingHost';
import { supabase } from '@/lib/supabase';
import { fetchNotebookArchive } from '@/lib/notebookArchive';
import { listNotebookDocuments } from '@/lib/notebookStorage';
import { listRecordings } from '@/lib/meetingRecordingStorage';
import { listRecordingArchivePage } from '@/lib/recordingCloud';
import { jasperMeetingRequest } from '@/lib/jasperMeetings';
import { workLink, workRequest, type WorkBoard, type WorkScope } from '@/lib/workspace';
import type { Prospect } from '@/lib/recruiter';
import { matchWorkspaceResults, workspaceSearchKinds, workspaceSearchResults, type WorkspaceSearchKind, type WorkspaceSearchResult } from '@/lib/workspaceSearch';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from './ui/dialog';
import { Command, CommandInput, CommandItem, CommandList } from './ui/command';
import { Button } from './ui/button';
import { WorkspaceObjectView, type WorkspaceObjectTarget } from './WorkspaceObjectView';

/** Global keyboard entry with no background archive ingestion. Close/account change unmounts all private results. */
export function WorkspaceSearch(): JSX.Element | null {
  const { user } = useAuth();
  const host = useMeetingHost();
  const [open, setOpen] = useState<boolean>(false);
  const [target, setTarget] = useState<WorkspaceObjectTarget | null>(null);
  const identity = useRef<string | null>(user?.id ?? null);
  useEffect(() => {
    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
      if (identity.current !== (session?.user.id ?? null) || !session) { setOpen(false); setTarget(null); }
      identity.current = session?.user.id ?? null;
    });
    return () => data.subscription.unsubscribe();
  }, []);
  useEffect(() => {
    const show = (): void => { if (user && (!host.active || host.minimized)) { setTarget(null); setOpen(true); } };
    const keyboard = (event: KeyboardEvent): void => { if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k' && !event.altKey && !event.isComposing && (!host.active || host.minimized)) { event.preventDefault(); show(); } };
    const context = (event: Event): void => {
      const detail = (event as CustomEvent<WorkspaceObjectTarget>).detail;
      if (user && (!host.active || host.minimized) && detail && workspaceSearchKinds.includes(detail.kind) && /^[a-z0-9-]{1,200}$/i.test(detail.objectID)) { setTarget(detail); setOpen(true); }
    };
    window.addEventListener('keydown', keyboard); window.addEventListener('whisper-workspace-search', show); window.addEventListener('whisper-workspace-ask', context);
    return () => { window.removeEventListener('keydown', keyboard); window.removeEventListener('whisper-workspace-search', show); window.removeEventListener('whisper-workspace-ask', context); };
  }, [user, host.active, host.minimized]);
  useEffect(() => { if (host.active && !host.minimized) { setOpen(false); setTarget(null); } }, [host.active, host.minimized]);
  if (!user || !open) return null;
  const close = (): void => { setOpen(false); setTarget(null); };
  return <Dialog open onOpenChange={(value) => { if (!value) close(); }}><DialogContent className="flex max-h-[85dvh] w-[calc(100%-2rem)] max-w-2xl flex-col overflow-hidden rounded-3xl p-0"><DialogHeader className="shrink-0 px-5 pb-2 pt-5"><DialogTitle>{target ? 'Ask Jasper about this' : 'Search workspace'}</DialogTitle><DialogDescription>{target ? 'One selected object. Review the sources and approve before asking.' : 'Meetings, private writing, recordings, People and work. Searching sends nothing to AI.'}</DialogDescription></DialogHeader>{target ? <div className="overflow-y-auto px-5 pb-5"><Button variant="ghost" className="mb-3 min-h-11" onClick={() => setTarget(null)}><ArrowLeft className="mr-2 h-4 w-4" />Back to search</Button><WorkspaceObjectView key={`${user.id}:${target.kind}:${target.objectID}:${target.archiveID ?? 'local'}`} owner={user.id} target={target} close={close} /></div> : <WorkspaceSearchResults key={user.id} owner={user.id} close={close} choose={setTarget} />}</DialogContent></Dialog>;
}

function WorkspaceSearchResults({ owner, close, choose }: { owner: string; close: () => void; choose: (target: WorkspaceObjectTarget) => void }): JSX.Element {
  const navigate = useNavigate(); const location = useLocation();
  const [query, setQuery] = useState<string>('');
  const [kind, setKind] = useState<WorkspaceSearchKind>('All');
  const [instance] = useState<string>(() => crypto.randomUUID());
  const [scope, setScope] = useState<WorkScope>(() => {
    const params = new URLSearchParams(location.search); const space = params.get('space');
    return { space: location.pathname === '/work' && space && /^[a-f0-9-]{36}$/i.test(space) ? space : owner, team: location.pathname === '/work' && params.get('team') === '1' };
  });
  const base = ['workspace-search', owner, instance];
  const defaults = { gcTime: 0, retry: false as const, refetchOnWindowFocus: true };
  const meetings = useInfiniteQuery({ ...defaults, queryKey: [...base, 'meetings'], initialPageParam: 0, queryFn: ({ pageParam, signal }) => fetchNotebookArchive(owner, pageParam, signal, true), getNextPageParam: (last, pages) => last.hasMore ? pages.length : undefined });
  const notes = useQuery({ ...defaults, queryKey: [...base, 'notes'], queryFn: async ({ signal }) => { const value = await listNotebookDocuments(owner); signal.throwIfAborted(); return value; } });
  const local = useQuery({ ...defaults, queryKey: [...base, 'recordings-local'], queryFn: async ({ signal }) => { const value = await listRecordings(owner); signal.throwIfAborted(); return value; } });
  const recordings = useInfiniteQuery({ ...defaults, queryKey: [...base, 'recordings'], initialPageParam: undefined as string | undefined, queryFn: ({ pageParam, signal }) => listRecordingArchivePage(owner, signal, pageParam), getNextPageParam: (last) => last.nextCursor });
  const people = useInfiniteQuery({ ...defaults, queryKey: [...base, 'people'], initialPageParam: 0, queryFn: async ({ pageParam, signal }) => {
    const { data, error } = await supabase.from('whisper_recruiter_prospects').select('*').eq('recruiter_id', owner).order('updated_at', { ascending: false }).order('id').range(pageParam * 50, pageParam * 50 + 49).abortSignal(signal);
    if (error) throw new Error('People unavailable'); return (data ?? []) as Prospect[];
  }, getNextPageParam: (last, pages) => last.length === 50 ? pages.length : undefined });
  const teams = useQuery({ ...defaults, queryKey: [...base, 'teams'], queryFn: ({ signal }) => jasperMeetingRequest<{ teams: { id: string; name: string }[] }>(owner, 'clients/teams', undefined, signal) });
  const work = useQuery({ ...defaults, queryKey: [...base, 'work', scope.space, scope.team], queryFn: ({ signal }) => workRequest<WorkBoard>(owner, scope, '', undefined, signal) });
  const rows = useMemo(() => workspaceSearchResults(owner,
    meetings.isError && !meetings.isFetchNextPageError ? [] : meetings.data?.pages.flatMap((p) => p.meetings) ?? [],
    notes.isError ? [] : notes.data ?? [], local.isError ? [] : local.data ?? [],
    people.isError && !people.isFetchNextPageError ? [] : people.data?.pages.flat() ?? [],
    work.isError ? [] : work.data?.items ?? [],
    recordings.isError && !recordings.isFetchNextPageError ? [] : recordings.data?.pages.flatMap((p) => p.items) ?? []),
    [owner, meetings.data, meetings.isError, meetings.isFetchNextPageError, notes.data, notes.isError, recordings.data, recordings.isError, recordings.isFetchNextPageError, local.data, local.isError, people.data, people.isError, people.isFetchNextPageError, work.data, work.isError]);
  const shown = useMemo(() => matchWorkspaceResults(rows, query, kind), [rows, query, kind]);
  const sources = [{ name: 'Meetings', value: meetings }, { name: 'Private writing', value: notes }, { name: 'Local recordings', value: local }, { name: 'Cloud recordings', value: recordings }, { name: 'People', value: people }, { name: 'Work', value: work }, { name: 'Teams', value: teams }];
  const open = (row: WorkspaceSearchResult): void => {
    if (row.kind === 'People' || row.kind === 'Recordings') { choose({ kind: row.kind, objectID: row.objectID, archiveID: row.archiveID, revision: row.revision }); return; }
    const type = row.kind === 'Meetings' ? 'meeting' : row.kind === 'Notes' ? 'note' : 'recording';
    const url = row.kind === 'Work' ? new URL(workLink(scope, row.objectID)) : new URL(`/notebook?portal=workspace&${type}=${encodeURIComponent(row.objectID)}`, window.location.origin);
    navigate(url.pathname + url.search); close();
  };
  return <Command label="Search workspace" shouldFilter={false} className="min-h-0 rounded-none" onKeyDownCapture={(event) => { if ((event.target as HTMLElement).closest('button,select')) event.stopPropagation(); }}><CommandInput aria-label="Search workspace" placeholder="Search a title, name or phrase…" value={query} onValueChange={setQuery} /><div className="flex shrink-0 flex-wrap gap-1 border-b p-2" aria-label="Search types">{workspaceSearchKinds.map((type) => <Button key={type} variant={kind === type ? 'secondary' : 'ghost'} className="h-11 rounded-full px-3 text-xs" aria-pressed={kind === type} onClick={() => setKind(type)}>{type}</Button>)}</div><CommandList className="max-h-[45dvh] min-h-28 px-2"><div role="status" className="px-3 py-2 text-xs text-muted-foreground">{sources.some((s) => s.value.isFetching) ? 'Loading permitted sources…' : `${shown.length} matches on loaded pages`}</div>{shown.map((row) => <div key={row.id} className="flex items-center border-b border-border/40"><CommandItem value={row.id} onSelect={() => open(row)} className="min-h-16 min-w-0 flex-1 gap-3 rounded-xl"><FileText className="h-4 w-4 shrink-0 text-muted-foreground" /><span className="min-w-0"><span className="block truncate font-medium">{row.title}</span><span className="block text-xs text-muted-foreground">{row.kind}{row.kind === 'Recordings' ? ` · ${row.archiveID ? 'Cloud backup' : 'This device'} · v${row.revision ?? 0}` : ''} · {row.date.slice(0, 10)}</span></span></CommandItem><Button variant="ghost" className="h-11 w-11 shrink-0 rounded-full p-0" aria-label={`Ask Jasper about this: ${row.title}`} title="Ask Jasper about this" onClick={() => choose({ kind: row.kind, objectID: row.objectID, archiveID: row.archiveID, revision: row.revision, scope: row.kind === 'Work' ? { ...scope } : undefined, ask: true })}><Sparkles className="h-4 w-4" /></Button></div>)}{shown.length === 0 && <p className="px-3 py-6 text-sm text-muted-foreground">No matching items on loaded pages. Try another word or load older items.</p>}</CommandList><div className="max-h-44 shrink-0 overflow-y-auto border-t px-4 py-3 text-xs"><label className="flex min-h-11 items-center gap-3">Work scope<select className="min-h-11 min-w-0 flex-1 rounded-xl border bg-background px-3" value={`${scope.team ? 'team' : 'private'}:${scope.space}`} onChange={(event) => { const [type, space] = event.target.value.split(':'); setScope({ space, team: type === 'team' }); }}><option value={`private:${owner}`}>My private work</option>{scope.space !== owner && !scope.team && <option value={`private:${scope.space}`}>Invited workspace</option>}{teams.data?.teams.map((team) => <option key={team.id} value={`team:${team.id}`}>{team.name}</option>)}</select></label><p className="text-muted-foreground">Loaded titles, saved notes and permitted transcripts. People is your private relationship list; work covers the selected board. Older pages and other devices may have more.</p>{sources.filter((s) => s.value.isError).map((source) => <p key={source.name} role="alert" className="mt-2">{source.name} couldn’t load. <button className="min-h-11 underline" onClick={() => void source.value.refetch()}>Retry</button></p>)}{recordings.data?.pages.some((p) => p.issues > 0) && <p className="mt-2">Some recording metadata needs attention; older pages remain searchable.</p>}<div className="mt-2 flex flex-wrap gap-1">{meetings.hasNextPage && <Button variant="ghost" className="h-11 text-xs" disabled={meetings.isFetching} onClick={() => void meetings.fetchNextPage()}>Older meetings</Button>}{recordings.hasNextPage && <Button variant="ghost" className="h-11 text-xs" disabled={recordings.isFetching} onClick={() => void recordings.fetchNextPage()}>Older recordings</Button>}{people.hasNextPage && <Button variant="ghost" className="h-11 text-xs" disabled={people.isFetching} onClick={() => void people.fetchNextPage()}>More people</Button>}</div></div></Command>;
}
