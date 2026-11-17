import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { ArrowUpRight, Check, ChevronRight, Folder, FolderOpen, FolderPlus, Inbox, MoreHorizontal, Search, Star } from 'lucide-react';
import { toast } from 'sonner';
import { useAuth } from '@/hooks/useAuth';
import { fetchNotebookArchive } from '@/lib/notebookArchive';
import { fetchMeeting, fetchNotebookPrefs, saveNotebookPref, type WhisperMeeting } from '@/lib/meetings';
import { jasperLibrarySchema, jasperMeetingRequest, loadJasperLibrary, type JasperLibrary } from '@/lib/jasperMeetings';
import { MeetingNotesScreen } from '@/components/MeetingNotesScreen';
import { MeetingRecordingLibrary } from '@/components/MeetingRecordingLibrary';
import { NotebookRecordingSources } from '@/components/NotebookRecordingSources';
import { JasperMeetingAssistant } from '@/components/JasperMeetingAssistant';
import { JasperSidekickMascot } from '@/components/JasperSidekickMascot';
import { JasperMeetingPreferences } from '@/components/JasperMeetingPreferences';
import { JasperUpcomingMeetings } from '@/components/JasperUpcomingMeetings';
import { JasperEarlierWriting } from '@/components/JasperMeetingSavedContent';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';
import { cn } from '@/lib/utils';

/** Legacy links open the same original notes; organization never deletes content. */
export default function Notebook(): JSX.Element {
  const { user } = useAuth();
  return user ? <MeetingsLibrary key={user.id} owner={user.id} /> : <p className="p-8 text-center">Sign in to see your meetings.</p>;
}
function MeetingsLibrary({ owner }: { owner: string }): JSX.Element {
  const [params, setParams] = useSearchParams();
  const client = useQueryClient();
  const [query, setQuery] = useState<string>('');
  const [folder, setFolder] = useState<string>('all');
  const [tab, setTab] = useState<'meetings' | 'jasper' | 'upcoming'>(params.get('view') === 'upcoming' ? 'upcoming' : params.get('view') === 'jasper' || params.get('q') ? 'jasper' : 'meetings');
  // A handed-off question (for example from Jasper Intelligence) only prefills the composer; asking still requires scope approval.
  const [handoffQuestion] = useState<string | undefined>(() => params.get('q')?.trim().slice(0, 600) || undefined);
  const [selected, setSelected] = useState<WhisperMeeting | null>(null);
  const [recordings, setRecordings] = useState<boolean>(!!params.get('recording'));
  const [earlier, setEarlier] = useState<boolean>(!!params.get('note'));
  const [preferences, setPreferences] = useState<boolean>(false);
  const [folderDialog, setFolderDialog] = useState<boolean>(false);
  const [folderName, setFolderName] = useState<string>('');
  const [renameID, setRenameID] = useState<string | null>(null);
  const [dragged, setDragged] = useState<string | null>(null);
  const [dropTarget, setDropTarget] = useState<string | null>(null);
  const [filing, setFiling] = useState<string | null>(null);
  const rows = useRef<Map<string, HTMLElement>>(new Map());
  const folders = useRef<Map<string, HTMLButtonElement>>(new Map());
  const mounted = useRef<boolean>(true);
  const meetingID = params.get('meeting'), recordingID = params.get('recording');
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
  const archive = useInfiniteQuery({ queryKey: ['meeting-notes-list', owner, meetingID], initialPageParam: 0, queryFn: async ({ pageParam, signal }) => { if (!meetingID) return fetchNotebookArchive(owner, pageParam, signal, true); const meeting = await fetchMeeting(meetingID); return { meetings: meeting ? [meeting] : [], hasMore: false }; }, getNextPageParam: (page, pages) => page.hasMore ? pages.length : undefined });
  const library = useQuery({ queryKey: ['jasper-library', owner], queryFn: ({ signal }) => loadJasperLibrary(owner, signal) });
  const prefs = useQuery({ queryKey: ['notebook-prefs', owner], queryFn: () => fetchNotebookPrefs(owner) });
  const organize = useMutation({
    mutationFn: async (fields: Record<string, unknown>) => {
      const current = client.getQueryData<JasperLibrary>(['jasper-library', owner]);
      if (!current) throw new Error('Load your folders before making changes.');
      return jasperLibrarySchema.parse(await jasperMeetingRequest(owner, 'library', { ...fields, revision: current.revision }));
    },
    onSuccess: (value) => { if (!mounted.current) return; client.setQueryData(['jasper-library', owner], value); setFolderDialog(false); setFolderName(''); },
    onError: (error: Error) => { if (mounted.current) { toast.error(error.message); void library.refetch(); } },
  });
  const favorite = useMutation({ mutationFn: (meeting: WhisperMeeting) => saveNotebookPref(owner, meeting.id, { isFavorite: !prefs.data?.prefs[meeting.id]?.is_favorite }), onSuccess: () => { void client.invalidateQueries({ queryKey: ['notebook-prefs', owner] }); }, onError: () => toast.error('Your favorite could not save. Try again.') });
  const openMeeting = useCallback((id: string): void => { void fetchMeeting(id).then((meeting) => { if (mounted.current) { if (meeting) setSelected(meeting); else toast.error('This meeting could not be opened.'); } }).catch(() => { if (mounted.current) toast.error('This meeting could not be opened.'); }); }, []);
  useEffect(() => { setSelected(null); }, [meetingID]);
  useEffect(() => { if (recordingID) setRecordings(true); }, [recordingID]);
  useEffect(() => { if (params.get('note')) setEarlier(true); }, [params]);
  const allMeetings = useMemo(() => [...new Map((archive.data?.pages.flatMap((page) => page.meetings) ?? []).map((meeting) => [meeting.id, meeting])).values()].filter((meeting) => meeting.status !== 'scheduled' || !!meeting.summary), [archive.data]);
  const meetings = useMemo(() => allMeetings.filter((meeting) => (folder === 'all' || (folder === 'unfiled' ? !library.data?.filings[meeting.id] : library.data?.filings[meeting.id] === folder)) && (!query.trim() || `${prefs.data?.prefs[meeting.id]?.custom_title ?? meeting.title} ${meeting.summary ?? ''} ${meeting.host_username}`.toLowerCase().includes(query.trim().toLowerCase()))).sort((a, b) => Number(!!prefs.data?.prefs[b.id]?.is_favorite) - Number(!!prefs.data?.prefs[a.id]?.is_favorite) || (b.ended_at ?? b.created_at ?? '').localeCompare(a.ended_at ?? a.created_at ?? '')), [allMeetings, folder, library.data, prefs.data, query]);
  const folderLabel = folder === 'all' ? 'All meetings' : folder === 'unfiled' ? 'Unfiled' : library.data?.folders.find((item) => item.id === folder)?.name ?? 'Meetings';
  const fileMeeting = async (id: string, destination: string | null): Promise<void> => {
    if (filing || organize.isPending || !mounted.current) return;
    const previous = library.data?.filings[id] ?? null;
    if (previous === destination) return;
    setFiling(id); setDragged(null); setDropTarget(null);
    try {
      // Animate only acknowledged moves. Failure leaves the original row and folder intact.
      const current = client.getQueryData<JasperLibrary>(['jasper-library', owner]);
      if (!current) throw new Error('Refresh folders before filing.');
      const value = jasperLibrarySchema.parse(await jasperMeetingRequest(owner, 'library', { action: 'file', meetingId: id, folderId: destination, revision: current.revision }));
      if (!mounted.current) return;
      const row = rows.current.get(id), target = folders.current.get(destination ?? 'unfiled');
      if (row?.animate && target && !window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
        const a = row.getBoundingClientRect(), b = target.getBoundingClientRect();
        await row.animate([{ transform: 'translate(0,0) scale(1)', opacity: 1 }, { transform: `translate(${b.x - a.x}px,${b.y - a.y}px) scale(0.15)`, opacity: 0 }], { duration: 380, easing: 'cubic-bezier(.4,0,.2,1)' }).finished.catch(() => undefined);
        target.animate([{ transform: 'scale(1)' }, { transform: 'scale(1.06)' }, { transform: 'scale(1)' }], { duration: 320 });
      }
      if (!mounted.current) return;
      client.setQueryData(['jasper-library', owner], value);
      toast.success(destination ? `Filed in ${value.folders.find((item) => item.id === destination)?.name ?? 'folder'}` : 'Moved to Unfiled', { action: { label: 'Undo', onClick: () => { if (mounted.current) organize.mutate({ action: 'file', meetingId: id, folderId: previous, expectedFolder: destination }); } } });
    } catch (error) { if (mounted.current) { toast.error(error instanceof Error ? error.message : 'Could not file this meeting.'); void library.refetch(); } }
    finally { if (mounted.current) setFiling(null); }
  };
  const folderButton = (id: string, name: string, count: number): JSX.Element => <button key={id} ref={(node) => { if (node) folders.current.set(id, node); else folders.current.delete(id); }} aria-label={name} aria-pressed={folder === id} onClick={() => setFolder(id)} onDragOver={(event) => { if (dragged && id !== 'all') { event.preventDefault(); setDropTarget(id); } }} onDragLeave={() => setDropTarget(null)} onDrop={(event) => { event.preventDefault(); if (dragged && id !== 'all') void fileMeeting(dragged, id === 'unfiled' ? null : id); }} className={cn('flex min-h-12 shrink-0 items-center gap-3 rounded-xl px-3 text-left text-sm transition-colors lg:w-full', folder === id ? 'bg-background font-semibold text-foreground shadow-sm' : 'text-muted-foreground hover:bg-muted', dropTarget === id && 'bg-muted ring-2 ring-foreground/30')}>
    {id === 'unfiled' ? <Inbox className="h-4 w-4" /> : folder === id ? <FolderOpen className="h-4 w-4" /> : <Folder className="h-4 w-4" />}<span className="min-w-0 flex-1 truncate">{name}</span><span aria-hidden="true" className="text-[11px] tabular-nums opacity-60">{count}</span>
  </button>;
  return <main className="mx-auto max-w-6xl px-4 pb-16 pt-6 md:px-8 md:pt-10">
    <header className="mb-7 flex items-center justify-between gap-4"><div><h1 className="text-3xl font-semibold tracking-tight">Meetings</h1><p className="mt-2 text-sm text-muted-foreground">Your conversations, notes and recordings.</p></div><DropdownMenu><DropdownMenuTrigger asChild><Button variant="ghost" size="icon" className="h-11 w-11" aria-label="Meeting library options"><MoreHorizontal className="h-5 w-5" /></Button></DropdownMenuTrigger><DropdownMenuContent align="end"><DropdownMenuItem onSelect={() => { setRecordings(true); const next = new URLSearchParams(params); next.delete('recording'); setParams(next); }}>All recordings</DropdownMenuItem><DropdownMenuItem onSelect={() => setEarlier(true)}>Earlier private writing</DropdownMenuItem><DropdownMenuItem onSelect={() => setPreferences(true)}>Personalize Jasper</DropdownMenuItem></DropdownMenuContent></DropdownMenu></header>
    <nav aria-label="Meeting library sections" className="mb-6 flex w-full max-w-md gap-1 rounded-2xl bg-muted p-1">{(['meetings', 'jasper', 'upcoming'] as const).map((item) => <button key={item} onClick={() => setTab(item)} aria-pressed={tab === item} className={cn('min-h-11 flex-1 rounded-xl px-4 text-sm transition-colors', tab === item ? 'bg-background font-semibold shadow-sm' : 'text-muted-foreground hover:text-foreground')}>{item === 'meetings' ? 'Meetings' : item === 'jasper' ? 'Sidekick' : 'Upcoming'}</button>)}</nav>
    {tab === 'meetings' && <button className="mb-6 flex w-full items-center gap-3 rounded-[24px] border border-border/60 bg-card px-4 py-3 text-left transition-colors hover:bg-muted" onClick={() => setTab('jasper')}><JasperSidekickMascot className="h-12" /><span className="flex-1"><span className="block text-sm font-semibold">Ask Jasper</span><span className="mt-1 block text-xs leading-5 text-muted-foreground">Find a decision, a detail or your next step.</span></span><ArrowUpRight className="h-5 w-5 shrink-0" /></button>}
    {library.error && <div role="alert" className="mb-4 rounded-xl border border-amber-300/40 p-3 text-xs leading-5">Folders could not load. Your original meeting notes are still available. <button className="min-h-11 underline" onClick={() => void library.refetch()}>Retry folders</button></div>}
    <div className={cn('gap-5 lg:grid lg:grid-cols-[220px_minmax(0,1fr)]', tab === 'upcoming' && 'hidden')}>
      <aside className="mb-4 min-w-0 self-start rounded-[24px] bg-card p-3"><div className="mb-2 flex items-center justify-between"><h2 className="text-[10px] font-semibold uppercase tracking-[0.16em] text-muted-foreground">My folders</h2><Button variant="ghost" size="icon" className="h-11 w-11" disabled={!library.data || !!filing} aria-label="New folder" onClick={() => { setRenameID(null); setFolderName(''); setFolderDialog(true); }}><FolderPlus className="h-4 w-4" /></Button></div><div className="mb-5 flex gap-1 overflow-x-auto pb-2 lg:block lg:space-y-1">
        {folderButton('all', 'All meetings', allMeetings.length)}
        {folderButton('unfiled', 'Unfiled', allMeetings.filter((m) => !library.data?.filings[m.id]).length)}
        {library.data?.folders.map((item) => <div key={item.id} className="flex shrink-0 items-center">{folderButton(item.id, item.name, allMeetings.filter((m) => library.data?.filings[m.id] === item.id).length)}<DropdownMenu><DropdownMenuTrigger asChild><Button variant="ghost" size="icon" className="h-11 w-11 shrink-0" aria-label={`Manage ${item.name}`}><MoreHorizontal className="h-3 w-3" /></Button></DropdownMenuTrigger><DropdownMenuContent><DropdownMenuItem onSelect={() => { setRenameID(item.id); setFolderName(item.name); setFolderDialog(true); }}>Rename folder</DropdownMenuItem><DropdownMenuItem disabled={!!filing || organize.isPending} onSelect={() => { if (window.confirm('Remove this folder? Meetings and recordings stay saved.')) organize.mutate({ action: 'folder.remove', id: item.id }, { onSuccess: () => { if (folder === item.id) setFolder('all'); } }); }}>Remove folder only</DropdownMenuItem></DropdownMenuContent></DropdownMenu></div>)}
      </div><p className="hidden px-2 text-[11px] leading-5 text-muted-foreground lg:block">Use File or drag into a folder.</p></aside>
      <div className="min-w-0">
        <section className={tab === 'meetings' ? 'block' : 'hidden'}>
          <div className="mb-4 flex items-center justify-between gap-3"><h2 className="text-xl font-semibold tracking-tight">{folderLabel}</h2><span className="text-xs text-muted-foreground">{meetings.length} loaded</span></div>
          <label className="mb-4 flex h-12 items-center gap-3 rounded-2xl border border-transparent bg-muted px-4"><Search className="h-4 w-4 text-muted-foreground" /><input aria-label="Search meetings" className="min-w-0 flex-1 bg-transparent text-sm outline-none" placeholder="Find a meeting…" value={query} onChange={(event) => setQuery(event.target.value)} /></label>
          <div className="space-y-2">{meetings.map((meeting) => {
            const filedIn = library.data?.folders.find((item) => item.id === library.data?.filings[meeting.id]);
            const date = new Date(meeting.ended_at ?? meeting.created_at ?? '');
            return <article key={meeting.id} ref={(node) => { if (node) rows.current.set(meeting.id, node); else rows.current.delete(meeting.id); }} draggable={!filing} onDragStart={(event) => { setDragged(meeting.id); event.dataTransfer.setData('text/plain', meeting.id); event.dataTransfer.effectAllowed = 'move'; }} onDragEnd={() => { setDragged(null); setDropTarget(null); }} className={cn('group relative flex items-center gap-1 rounded-[22px] border border-border/50 bg-card px-3 py-3 transition-colors hover:bg-muted sm:gap-3 sm:px-4', filing === meeting.id && 'opacity-50')}>
              <div className="hidden w-12 shrink-0 rounded-2xl bg-background py-2 text-center sm:block"><span className="block text-[10px] uppercase text-muted-foreground">{Number.isNaN(date.getTime()) ? '—' : date.toLocaleDateString(undefined, { month: 'short' })}</span><span className="text-xl font-medium tabular-nums">{Number.isNaN(date.getTime()) ? '—' : date.getDate()}</span></div>
              <button aria-label="Open note" className="min-h-14 min-w-0 flex-1 text-left" onClick={() => setSelected(meeting)}><h3 className="truncate text-sm font-semibold">{prefs.data?.prefs[meeting.id]?.custom_title ?? meeting.title}</h3><p className="mt-1.5 text-xs text-muted-foreground">{meeting.host_username ? `@${meeting.host_username}` : 'Meeting'}{filedIn && <span className="ml-2 inline-flex items-center gap-1 text-muted-foreground"><Folder className="h-3 w-3" />{filedIn.name}</span>}</p></button>
              <Button variant="ghost" size="icon" className="h-11 w-11 shrink-0" aria-label={prefs.data?.prefs[meeting.id]?.is_favorite ? 'Unfavorite' : 'Favorite'} onClick={() => favorite.mutate(meeting)}><Star className={cn('h-4 w-4 text-muted-foreground/50', prefs.data?.prefs[meeting.id]?.is_favorite && 'fill-amber-400 text-amber-500')} /></Button>
              <DropdownMenu><DropdownMenuTrigger asChild><Button variant="ghost" className="h-11 shrink-0 gap-1.5 px-2 text-xs" aria-label={`File ${meeting.title}`} disabled={!!filing || organize.isPending}><Folder className="h-4 w-4" /><span className="hidden sm:inline">File</span></Button></DropdownMenuTrigger><DropdownMenuContent align="end">{library.data?.folders.map((item) => <DropdownMenuItem key={item.id} onSelect={() => void fileMeeting(meeting.id, item.id)}><Folder className="mr-2 h-4 w-4" />{item.name}{filedIn?.id === item.id && <Check className="ml-3 h-3 w-3" />}</DropdownMenuItem>)}<DropdownMenuItem onSelect={() => void fileMeeting(meeting.id, null)}>Unfile meeting</DropdownMenuItem></DropdownMenuContent></DropdownMenu>
              <ChevronRight className="hidden h-4 w-4 text-muted-foreground/40 sm:block" />
            </article>;
          })}</div>
          {archive.isPending && <p role="status" className="py-12 text-center text-sm text-muted-foreground">Opening your meetings…</p>}
          {archive.error && <div role="alert" className="py-8 text-sm">Meeting history could not load. <Button variant="ghost" onClick={() => void archive.refetch()}>Try again</Button></div>}
          {!archive.isPending && !archive.error && !meetings.length && <div className="py-14 text-center"><FolderOpen className="mx-auto mb-3 h-8 w-8 text-muted-foreground" /><h3 className="text-xl font-semibold tracking-tight">{query ? 'No matching meetings' : 'No meetings here yet'}</h3><p className="mx-auto mt-2 max-w-xs text-xs leading-6 text-muted-foreground">{query ? 'Try another title or host, or load older meetings.' : folder === 'all' ? 'Your past meetings will live here, with their notes and recordings.' : 'Choose All meetings, then File to put a conversation here.'}</p></div>}
          {archive.hasNextPage && <Button variant="ghost" className="mt-4 h-11 w-full" disabled={archive.isFetchingNextPage} onClick={() => void archive.fetchNextPage()}>Load older meetings</Button>}
          <p className="mt-4 text-[10px] text-muted-foreground">Search covers titles, notes and hosts in loaded history.</p>
        </section>
        <div className={tab === 'jasper' ? 'flex h-[min(680px,75dvh)] flex-col rounded-[28px] bg-card p-4 sm:p-6' : 'hidden'}><JasperMeetingAssistant owner={owner} folderID={['all', 'unfiled'].includes(folder) ? undefined : folder} embedded onOpenMeeting={openMeeting} initialQuestion={handoffQuestion} /></div>
      </div>
    </div>
    {tab === 'upcoming' && <JasperUpcomingMeetings owner={owner} />}
    <Dialog open={folderDialog} onOpenChange={setFolderDialog}><DialogContent><DialogHeader><DialogTitle>{renameID ? 'Rename folder' : 'New meeting folder'}</DialogTitle><DialogDescription>A private home for related conversations.</DialogDescription></DialogHeader><form className="space-y-4" onSubmit={(event) => { event.preventDefault(); organize.mutate({ action: renameID ? 'folder.rename' : 'folder.create', id: renameID, name: folderName }); }}><input autoFocus aria-label="Folder name" className="h-12 w-full rounded-xl border border-border bg-background px-3" maxLength={60} value={folderName} onChange={(event) => setFolderName(event.target.value)} placeholder="For example: Creator partnerships" /><Button type="submit" className="h-11 w-full" disabled={!folderName.trim() || organize.isPending}>{renameID ? 'Save folder' : 'Create folder'}</Button></form></DialogContent></Dialog>
    <Dialog open={preferences} onOpenChange={setPreferences}><DialogContent className="max-h-[85dvh] overflow-y-auto"><DialogHeader><DialogTitle>Personalize Jasper</DialogTitle></DialogHeader>{library.data ? <JasperMeetingPreferences owner={owner} library={library.data} onClose={() => setPreferences(false)} /> : <Button onClick={() => void library.refetch()}>Load preferences</Button>}</DialogContent></Dialog>
    <Dialog open={recordings} onOpenChange={setRecordings}><DialogContent className="max-h-[85dvh] overflow-y-auto sm:max-w-3xl"><DialogHeader><DialogTitle>Meeting recordings</DialogTitle></DialogHeader>{recordingID ? <NotebookRecordingSources note={{ id: recordingID, ownerId: owner, meetingId: meetingID, recordingIds: [recordingID] }} /> : <MeetingRecordingLibrary ownerId={owner} meetingId={meetingID} />}</DialogContent></Dialog>
    <Dialog open={earlier} onOpenChange={setEarlier}><DialogContent className="max-h-[85dvh] overflow-y-auto"><DialogHeader><DialogTitle>Earlier private writing</DialogTitle></DialogHeader><JasperEarlierWriting owner={owner} noteID={params.get('note') ?? undefined} /></DialogContent></Dialog>
    {selected && <MeetingNotesScreen key={`${owner}:${selected.id}`} meetingId={selected.id} recordingId={recordingID} title={prefs.data?.prefs[selected.id]?.custom_title ?? selected.title} notes={selected.summary ?? ''} onClose={() => setSelected(null)} />}
  </main>;
}
