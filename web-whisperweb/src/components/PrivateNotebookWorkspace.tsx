import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useSearchParams } from "react-router-dom";
import { ArrowLeft, FileText, Plus, Search, MoreHorizontal, AudioLines, Check } from "lucide-react";
import { toast } from "sonner";
import { cn } from "@/lib/utils";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Button } from "@/components/ui/button";
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";
import { NotebookLiveTranscript } from "./NotebookLiveTranscript";
import { NOTEBOOK_TEMPLATES, newNotebookDocument, type NotebookDocument, type NotebookSource } from "@/lib/notebookDocument";
import { deleteNotebookDocument, listNotebookDocuments, saveNotebookDocument } from "@/lib/notebookStorage";
import { useNotebookSync } from "@/hooks/useNotebookSync";
import type { WhisperMeeting } from "@/lib/meetings";
import { NotebookArchivePicker } from "./NotebookArchivePicker";
import { NotebookRecordingBackup } from "./NotebookRecordingBackup";
import { NotebookQuestions } from "./NotebookQuestions";
import { PrivateNotebookEditor } from "./PrivateNotebookEditor";
import { NotebookRecordingSources } from "./NotebookRecordingSources";
import { listRecordings, recordingReadIssues } from "@/lib/meetingRecordingStorage";
import { listRecordingArchives, listRecordingArchivePage } from "@/lib/recordingCloud";
import { ensureRecordingNote } from "@/lib/recordingNotebook";
import type { MeetingRecording } from "@/lib/meetingRecordingModel";
import { listNotebookRecoveries, type NotebookRecovery } from "@/lib/notebookRecovery";

type MediaScope = Pick<NotebookDocument, "id" | "ownerId" | "meetingId" | "recordingIds"> & { title: string };

/** One parent-owned selection; neither meeting metadata nor Jasper introduces extra context. */
export function PrivateNotebookWorkspace({ userId, archiveMeeting, onArchiveClose, liveMeetingID }: { liveMeetingID?: string; userId: string; archiveMeeting?: WhisperMeeting | null; onArchiveClose?: () => void }): JSX.Element {
  const client = useQueryClient();
  const [params, setParams] = useSearchParams();
  const meetingId = liveMeetingID ?? params.get("meeting");
  const [storedContext, setStoredContext] = useState<{ sources: NotebookSource[]; label: string; destination: string; owner: string } | null>(null);
  const requested = liveMeetingID ? null : params.get("note") ?? params.get("recording");
  const [titleContainer, setTitleContainer] = useState<HTMLDivElement | null>(null);
  const [archiveOpen, setArchiveOpen] = useState<boolean>(false);
  const [toolsOpen, setToolsOpen] = useState<boolean>(false);
  const [query, setQuery] = useState<string>("");
  const [folder, setFolder] = useState<string>("");
  const [recordingsOnly, setRecordingsOnly] = useState<boolean>(false);
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [selected, setSelected] = useState<NotebookDocument | null>(null);
  const externalContext = storedContext?.owner === userId && storedContext.destination === selected?.id && selectedIds.length === 1 ? storedContext : null;
  const setExternalContext = (context: { sources: NotebookSource[]; label: string } | null): void => setStoredContext(context && selected ? { ...context, destination: selected.id, owner: userId } : null);
  const selectedSignature = selectedIds.join(",");
  useEffect(() => { setStoredContext(null); }, [selectedSignature, userId]);
  const [selecting, setSelecting] = useState<boolean>(false);
  const [showFocus, setShowFocus] = useState<boolean>(false);
  const [mediaScope, setMediaScope] = useState<MediaScope | null>(null);
  const [editorBusy, setEditorBusy] = useState<boolean>(false);
  const busyRef = useRef<boolean>(false);
  const editor = useRef<{ importTranscript: (text: string) => void } | null>(null);
  const busyChanged = useCallback((busy: boolean) => { busyRef.current = busy; setEditorBusy(busy); }, []);
  const canSwitch = (): boolean => { if (!busyRef.current) return true; toast("Your note is saving. Please wait, or use Retry in the open note."); return false; };
  const openNote = (note: NotebookDocument): void => {
    if (!canSwitch()) return;
    setExternalContext(null); setSelectedIds([note.id]); setSelected(note); setSelecting(false); setShowFocus(true);
    setMediaScope({ id: note.id, ownerId: note.ownerId, meetingId: note.meetingId, title: note.title, recordingIds: note.recordingIds });
  };
  const openRecording = (record: MeetingRecording): void => {
    if (!canSwitch()) return;
    setExternalContext(null); setSelectedIds([]); setSelected(null); setSelecting(false); setShowFocus(true);
    setMediaScope({ id: record.id, ownerId: record.ownerId, meetingId: record.meetingId, title: record.title });
  };
  const sync = useNotebookSync(userId, selected?.id ?? null);
  const [deletion, setDeletion] = useState<NotebookDocument | null>(null);
  const [recoveries, setRecoveries] = useState<NotebookRecovery[]>(() => listNotebookRecoveries(userId));
  const beginOperation = useChatOperationGuard(userId, "personal-notebook");
  const queryKey = ["personal-notebook", userId] as const;
  const entries = useQuery({ queryKey, queryFn: () => listNotebookDocuments(userId), networkMode: "always" });
  const recordings = useQuery({ queryKey: ["recordings", userId], queryFn: () => listRecordings(userId), networkMode: "always", refetchInterval: 5000 });
  const archives = useInfiniteQuery({ queryKey: ["recording-cloud", userId, "notebook-all"], initialPageParam: undefined as string | undefined, queryFn: ({ signal, pageParam }) => listRecordingArchivePage(userId, signal, pageParam, null), getNextPageParam: (page) => page.nextCursor, gcTime: 0 });
  const requestedArchive = useQuery({ queryKey: ["recording-cloud", userId, "requested", requested], enabled: !!requested && /^[0-9a-f-]{36}$/i.test(requested), queryFn: ({ signal }) => listRecordingArchives(userId, signal, undefined, null, requested ?? undefined), gcTime: 0 });
  const recorded = useMemo(() => {
    const result = new Map<string, MeetingRecording>();
    for (const archive of [...(requestedArchive.data ?? []), ...(archives.data?.pages.flatMap((page) => page.items) ?? [])]) if (archive.owner_id === userId && !result.has(archive.recording_id)) result.set(archive.recording_id, archive.snapshot);
    for (const record of recordings.data ?? []) if (record.ownerId === userId) result.set(record.id, record);
    return [...result.values()];
  }, [archives.data, requestedArchive.data, recordings.data, userId]);
  const savedNote = (saved: NotebookDocument): void => { client.setQueryData<NotebookDocument[]>(queryKey, (existing) => [saved, ...(existing ?? []).filter((note) => note.id !== saved.id)]); };
  const connectRecording = useMutation({ networkMode: "always", mutationFn: async (record: MeetingRecording) => {
    const check = beginOperation(); if (record.ownerId !== userId || busyRef.current) throw new Error("Finish saving the open note first.");
    const saved = await ensureRecordingNote(record, check); check(); return saved;
  }, onSuccess: (saved) => { savedNote(saved); openNote(saved); }, onError: (error: Error) => toast.error(error.message) });
  const attachRecording = useMutation({ networkMode: "always", mutationFn: async (record: MeetingRecording) => {
    const check = beginOperation(); const id = selected?.id;
    if (!id || busyRef.current || record.ownerId !== userId) throw new Error("Finish saving the note first.");
    const target = (await listNotebookDocuments(userId)).find((note) => note.id === id); check();
    if (!target || target.meetingId !== record.meetingId || busyRef.current) throw new Error("Reopen the saved note before attaching this recording.");
    const ids = [...new Set([...(target.recordingIds ?? (recorded.some((item) => item.id === target.id) ? [target.id] : [])), record.id])];
    if (ids.length > 30) throw new Error("A note can hold up to 30 recording attachments.");
    const saved = await saveNotebookDocument({ ...target, recordingIds: ids }, check); check(); return saved;
  }, onSuccess: (saved) => { savedNote(saved); setMediaScope((prior) => prior?.id === saved.id ? { ...prior, recordingIds: saved.recordingIds } : prior); }, onError: (error: Error) => toast.error(error.message) });
  const handledRequest = useRef<string | null>(null);
  useEffect(() => {
    if (!requested) { handledRequest.current = null; return; }
    if (handledRequest.current === requested || busyRef.current) return;
    const found = entries.data?.find((note) => note.id === requested);
    if (found) { handledRequest.current = requested; setSelectedIds([found.id]); setSelected(found); setMediaScope({ id: found.id, ownerId: found.ownerId, meetingId: found.meetingId, title: found.title, recordingIds: found.recordingIds }); setShowFocus(true); setSelecting(false); return; }
    const recording = recorded.find((item) => item.id === requested);
    if (recording && (entries.data || entries.isError)) { handledRequest.current = requested; setSelectedIds([]); setSelected(null); setMediaScope({ id: recording.id, ownerId: recording.ownerId, meetingId: recording.meetingId, title: recording.title }); setShowFocus(true); setSelecting(false); }
  }, [requested, entries.data, entries.isError, editorBusy, recorded]);
  const create = useMutation({ networkMode: "always", mutationFn: async (templateId: string) => {
    const check = beginOperation(); if (busyRef.current) throw new Error("Finish saving the open note first.");
    if ((await listNotebookDocuments(userId)).length >= 200) throw new Error("Notebook is full (200 notes). Export and remove a note first."); check();
    const document = newNotebookDocument(userId, liveMeetingID ?? null); document.templateId = templateId;
    const saved = await saveNotebookDocument(document, check); check(); return saved;
  }, onSuccess: (saved) => { savedNote(saved); openNote(saved); }, onError: (error: Error) => toast.error(error.message) });
  const recover = useMutation({ networkMode: "always", mutationFn: async (recovery: NotebookRecovery) => {
    const check = beginOperation(); if (busyRef.current || recovery.document.ownerId !== userId) throw new Error("Finish saving the open note first.");
    if ((await listNotebookDocuments(userId)).length >= 200) throw new Error("Notebook is full (200 notes). Export and remove a note first."); check();
    const current = listNotebookRecoveries(userId).find((entry) => entry.key === recovery.key)?.document ?? recovery.document;
    const saved = await saveNotebookDocument({ ...current, id: crypto.randomUUID(), storageRevision: 0, syncEnabled: true, isMeetingWriting: false, cloudRevision: undefined, syncedStorageRevision: undefined, syncOperationId: undefined, deletedAt: undefined, title: `Recovered · ${current.title || "Untitled note"}`.slice(0, 160) }, check); check(); return saved;
  }, onSuccess: (saved) => { setRecoveries(listNotebookRecoveries(userId)); savedNote(saved); openNote(saved); }, onError: (error: Error) => toast.error(error.message) });
  const remove = useMutation({ networkMode: "always", mutationFn: async (document: NotebookDocument) => { const check = beginOperation(); if (busyRef.current) throw new Error("Finish saving your note before deleting."); await deleteNotebookDocument(document, check); check(); }, onSuccess: (_, document) => {
    setDeletion(null); setSelectedIds((ids) => ids.filter((id) => id !== document.id)); if (selected?.id === document.id) { setSelected(null); busyChanged(false); } void client.invalidateQueries({ queryKey });
  }, onError: (error: Error) => { toast.error(error.message); setDeletion(null); void client.invalidateQueries({ queryKey }); } });
  const folders = useMemo(() => [...new Set((entries.data ?? []).map((note) => note.folder).filter(Boolean))].sort(), [entries.data]);
  const selectedMissing = !!selected && !!entries.data && !entries.data.some((note) => note.id === selected.id);
  const focused = selected ? entries.data?.find((note) => note.id === selected.id) ?? selected : null;
  const picked = selectedIds.flatMap((id) => { const note = entries.data?.find((item) => item.id === id); return note ? [note] : []; });
  const filtered = (entries.data ?? []).filter((note) => !recordingsOnly && (!folder || note.folder === folder) && (!query.trim() || [note.title, note.notes, note.people, note.folder, note.transcript].some((value) => value.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase()))));
  const unmatched = recorded.filter((record) => (recordingsOnly || !(entries.data ?? []).some((note) => note.id === record.id || note.recordingIds?.includes(record.id))) && (recordingsOnly || !folder) && [record.title, ...record.transcript.map((passage) => passage.text)].some((text) => text.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase())));
  const rows = [...filtered.map((note) => ({ id: note.id, createdAt: note.createdAt, note, record: null as MeetingRecording | null })), ...unmatched.map((record) => ({ id: record.id, createdAt: record.createdAt, note: null as NotebookDocument | null, record }))].sort((a, b) => b.createdAt.localeCompare(a.createdAt) || a.id.localeCompare(b.id));
  const toggle = (note: NotebookDocument): void => {
    if (!canSwitch()) return;
    if (!selectedIds.includes(note.id) && selectedIds.length >= 8) { toast("Choose up to eight notes."); return; }
    const next = selectedIds.includes(note.id) ? selectedIds.filter((id) => id !== note.id) : [...selectedIds, note.id];
    const only = next.length === 1 ? entries.data?.find((item) => item.id === next[0]) ?? null : null;
    setSelectedIds(next); setSelected(only);
    if (only) setMediaScope({ id: only.id, ownerId: only.ownerId, meetingId: only.meetingId, title: only.title, recordingIds: only.recordingIds });
  };
  const clear = (): void => { if (!canSwitch()) return; setSelectedIds([]); setSelected(null); setSelecting(false); setShowFocus(false); setParams((previous) => { const next = new URLSearchParams(previous); next.delete("note"); next.delete("recording"); return next; }, { replace: true }); };

  return <section className="mb-8" aria-label="Personal notebook">
    <header className="mb-5 flex items-center justify-between gap-3"><div><h1 className="font-serif text-4xl tracking-tight">Notebook</h1><p className="mt-2 text-xs text-muted-foreground">Your words. A little more clarity.</p></div><div className="flex items-center gap-1"><Button variant="ghost" size="icon" className="h-11 w-11" aria-label="Notebook options" aria-expanded={toolsOpen} onClick={() => setToolsOpen((value) => !value)}><MoreHorizontal className="h-5 w-5" /></Button><Button className="h-11 rounded-full px-4" disabled={editorBusy || create.isPending || entries.isPending || entries.isError} onClick={() => create.mutate("general")}><Plus className="mr-1 h-4 w-4" />New note</Button></div></header>
    {toolsOpen && <div className="mb-5 space-y-3 border-y border-border py-4"><p className="text-xs leading-relaxed text-muted-foreground">Notes save privately to your account with offline recovery. Existing writing joins account saving after checking other devices. Recording backup is separate. Nothing is shared with attendees.</p><p role="status" className="text-xs">{sync.isPending ? "Syncing…" : sync.isError ? sync.error.message : sync.data ?? "Checking private sync…"}</p><Button variant="ghost" className="h-11 text-xs" disabled={sync.isPending || editorBusy} onClick={() => sync.mutate()}>Retry / refresh sync</Button><details><summary className="min-h-11 cursor-pointer py-3 text-xs">Start from a format</summary><div className="flex flex-wrap gap-2">{NOTEBOOK_TEMPLATES.map((template) => <Button key={template.id} variant="outline" className="h-11 rounded-full text-xs" disabled={editorBusy || create.isPending || entries.isError} onClick={() => create.mutate(template.id)}>{template.label}</Button>)}</div></details></div>}
    <NotebookRecordingBackup key={userId} owner={userId} />
    <Button variant="outline" className="mb-4 h-11 rounded-full" disabled={editorBusy} onClick={() => { if (canSwitch()) setArchiveOpen(true); }}><FileText className="mr-2 h-4 w-4 text-[#F22659]" />Notes archive · from meetings</Button>
    {(archiveOpen || archiveMeeting) && <NotebookArchivePicker key={`${userId}:${archiveMeeting?.id ?? meetingId ?? "all"}`} initialMeeting={archiveMeeting} ownerId={userId} meetingId={archiveMeeting?.id ?? meetingId} adding={selecting} disabled={editorBusy || (selecting && selectedIds.length >= 8)} onClose={() => { setArchiveOpen(false); onArchiveClose?.(); }} onChoose={(saved) => {
      savedNote(saved); setArchiveOpen(false); onArchiveClose?.();
      if (selecting) {
        if (!selectedIds.includes(saved.id) && selectedIds.length < 8) {
          const next = [...selectedIds, saved.id]; setSelectedIds(next); setSelected(next.length === 1 ? saved : null);
          if (next.length === 1) setMediaScope({ id: saved.id, ownerId: saved.ownerId, meetingId: saved.meetingId, title: saved.title, recordingIds: saved.recordingIds });
        }
      } else openNote(saved);
    }} />}
    {!!recoveries.length && <details className="mb-4 border-b border-border"><summary className="min-h-11 cursor-pointer py-3 text-sm font-semibold">Unsaved writing found</summary><p className="text-xs text-muted-foreground">Recover as a new copy. Original recoveries remain available.</p>{recoveries.map((entry) => <Button key={entry.key} variant="ghost" className="h-11 max-w-full truncate text-xs" disabled={recover.isPending || editorBusy} onClick={() => recover.mutate(entry)}>Recover: {entry.document.title || "Untitled note"}</Button>)}</details>}
    <div className="grid min-w-0 gap-6 md:grid-cols-[260px_minmax(0,1fr)] lg:grid-cols-[300px_minmax(0,1fr)]">
      <aside aria-label="Note list" className={cn("min-w-0 md:sticky md:top-4 md:max-h-[calc(100dvh-120px)] md:self-start md:overflow-y-auto md:block md:border-r md:border-border md:pr-5", showFocus && "hidden")}>
        <div className="flex items-center gap-2"><label className="flex min-h-11 min-w-0 flex-1 items-center gap-2 border-b border-border"><Search className="h-4 w-4 shrink-0 text-muted-foreground" /><input aria-label="Search personal notebook" placeholder="Search notes & recordings" value={query} onChange={(event) => setQuery(event.target.value)} className="min-w-0 flex-1 bg-transparent text-sm outline-none" /></label><Button variant="ghost" className="h-11 px-2 text-xs" aria-pressed={selecting} onClick={() => { if (canSwitch()) setSelecting((value) => !value); }}>{selecting ? "Done" : "Select"}</Button></div>
        <div className="flex gap-1 py-2"><Button variant={recordingsOnly ? "ghost" : "secondary"} className="h-11 rounded-full text-xs" onClick={() => setRecordingsOnly(false)}>Notes & recordings</Button><Button variant={recordingsOnly ? "secondary" : "ghost"} className="h-11 rounded-full text-xs" onClick={() => setRecordingsOnly(true)}>All recordings</Button></div>
        {!!folders.length && <select aria-label="Filter folder" value={folder} onChange={(event) => setFolder(event.target.value)} className="mt-2 min-h-11 w-full bg-background text-xs"><option value="">All folders</option>{folders.map((name) => <option key={name}>{name}</option>)}</select>}
        {meetingId && <p className="py-3 text-xs text-muted-foreground">Matching meeting entries are marked below. Choose your notes; no context is selected automatically.</p>}
        {!!selectedIds.length && <div className="my-3 border-y border-border py-2"><p className="text-xs font-semibold">{selectedIds.length} selected</p><p className="mt-1 text-xs text-muted-foreground">{selectedIds.map((id) => entries.data?.find((note) => note.id === id)?.title || "Unavailable note").join(" · ")}</p><div className="flex gap-2"><Button variant="ghost" className="h-11 text-xs" onClick={clear}>Clear</Button><Button variant="outline" className="h-11 rounded-full text-xs" onClick={() => { if (canSwitch()) setShowFocus(true); }}>Work with selection</Button></div></div>}
        {entries.isPending && <p role="status" className="py-6 text-sm">Opening your notebook…</p>}
        {entries.isError && <div role="alert" className="py-4 text-sm"><p>{entries.error.message}</p><Button variant="ghost" className="h-11" onClick={() => void entries.refetch()}>Try again</Button></div>}
        <div className="divide-y divide-border">{rows.map(({ id, note, record }) => <article key={id} className="flex items-center gap-1 py-1"><button aria-pressed={selectedIds.includes(id)} aria-label={note ? `${note.title || "Untitled note"} ${note.notes || "Start writing"}` : `Open recording: ${record?.title || "Meeting recording"}`} className={cn("flex min-h-20 min-w-0 flex-1 items-start gap-3 rounded-xl px-2 py-4 text-left transition-colors hover:bg-muted/60", selectedIds.includes(id) && "bg-muted/70")} onClick={() => { if (note) { if (selecting) toggle(note); else openNote(note); } else if (record) openRecording(record); }}>
          {selecting && note ? <span className="mt-1 flex h-5 w-5 shrink-0 items-center justify-center rounded-full border border-foreground/40">{selectedIds.includes(id) && <Check className="h-3 w-3" />}</span> : record || !!note?.recordingIds?.length || recorded.some((item) => item.id === id) ? <AudioLines className="mt-1 h-4 w-4 shrink-0 text-[#F22659]" /> : <FileText className="mt-1 h-4 w-4 shrink-0 text-muted-foreground" />}
          <div className="min-w-0 flex-1"><h2 className="truncate text-sm font-semibold">{note?.title || record?.title || "Untitled note"}</h2><p className="mt-1 line-clamp-1 text-xs text-muted-foreground">{note ? note.notes || "Start writing…" : "Recording only · playback needs no note"}</p><p className="mt-2 text-[11px] text-muted-foreground">{(note?.createdAt ?? record?.createdAt)?.slice(0, 10)}{meetingId && (note?.meetingId ?? record?.meetingId) === meetingId ? " · Matching meeting" : ""}</p></div>
        </button>{note && <DropdownMenu><DropdownMenuTrigger asChild><Button size="icon" variant="ghost" className="h-11 w-11 shrink-0" aria-label={`Options for ${note.title || "untitled note"}`}><MoreHorizontal className="h-4 w-4" /></Button></DropdownMenuTrigger><DropdownMenuContent><DropdownMenuItem disabled={editorBusy} onSelect={() => setDeletion(note)} className="text-destructive">Delete note</DropdownMenuItem></DropdownMenuContent></DropdownMenu>}</article>)}</div>
        {!entries.isPending && !rows.length && <p className="py-10 text-sm text-muted-foreground">{query || folder ? "No matching notes" : "A little space to think. Start a new note."}</p>}
        {(recordingReadIssues(userId) > 0 || !!archives.data?.pages.some((page) => page.issues > 0)) && <p role="status" className="py-3 text-xs text-muted-foreground">Some recording metadata needs attention. Original media is retained; other recordings remain available.</p>}
        {(recordings.isError || archives.isError || requestedArchive.isError) && <Button variant="ghost" className="h-11 text-xs" onClick={() => { void recordings.refetch(); void archives.refetch(); if (requested) void requestedArchive.refetch(); }}>Retry recordings</Button>}
        {archives.hasNextPage && <Button variant="ghost" className="h-11 text-xs" disabled={archives.isFetchingNextPage} onClick={() => void archives.fetchNextPage()}>Load older recordings</Button>}
      </aside>
      <article aria-label="Selected note workspace" className={cn("min-w-0 md:block", !showFocus && "hidden")}>
        <Button variant="ghost" className="mb-3 h-11 -translate-x-3 text-xs md:hidden" onClick={() => { if (canSwitch()) setShowFocus(false); }}><ArrowLeft className="mr-2 h-4 w-4" />Notes & recordings · {selectedIds.length} selected</Button>
        {selectedIds.length > 1 && <header className="pb-6"><p className="text-xs font-semibold uppercase tracking-widest text-[#F22659]">Selected notes</p><h2 className="mt-3 font-serif text-3xl">Working with {selectedIds.length} notes</h2><p className="mt-3 text-sm text-muted-foreground">{picked.map((note) => note.title || "Untitled note").join(" · ")}</p></header>}
        <div ref={setTitleContainer} />
        {liveMeetingID && focused && selectedIds.length === 1 && <NotebookLiveTranscript key={`${userId}:${liveMeetingID}:${focused.id}`} owner={userId} meetingId={liveMeetingID} onChoose={setExternalContext} />}
        {focused?.recapCopiedAt && selectedIds.length === 1 && <p className="mb-3 text-xs text-muted-foreground">Private copy of a meeting-generated note · shared original unchanged</p>}
        {mediaScope && <div><p className="mb-2 text-xs text-muted-foreground">Recording sources · {mediaScope.title || "Untitled note"}{selectedIds.length > 1 ? " · playback only, not AI context" : ""}</p><NotebookRecordingSources key={`${userId}:${mediaScope.id}`} note={mediaScope} onContext={focused && selectedIds.length === 1 ? setExternalContext : undefined} onAttach={selectedIds.length === 1 && selected?.id === mediaScope.id && !selectedMissing && !editorBusy && !attachRecording.isPending ? (record) => attachRecording.mutate(record) : undefined} onImportTranscript={selectedIds.length === 1 && selected?.id === mediaScope.id && !selectedMissing ? (text) => editor.current?.importTranscript(text) : undefined} /></div>}
        {selectedMissing && <p role="status" className="mb-3 border border-border p-3 text-sm">This note is no longer listed in storage. Your open draft is kept here; export your writing before leaving. Deleted notes are not recreated.</p>}
        {focused && selectedIds.length === 1 && <PrivateNotebookEditor key={`${userId}:${focused.id}`} initial={focused} externalContext={externalContext} onClearExternal={() => setExternalContext(null)} syncError={sync.isError ? sync.error.message : undefined} onRetrySync={() => sync.mutate()} workspaceMode titleContainer={titleContainer} editorRef={editor} onBusyChange={busyChanged} onClose={() => { busyChanged(false); setSelected(null); setSelectedIds([]); setShowFocus(false); }} onSaved={(saved) => { if (saved) savedNote(saved); void client.invalidateQueries({ queryKey }); }} />}
        {!selectedIds.length && mediaScope && <div className="py-5"><h2 className="font-serif text-2xl">{mediaScope.title || "Recording only"}</h2><p className="my-3 text-sm text-muted-foreground">Playback is independent of your writing. A deleted note will never be recreated.</p><Button variant="outline" className="h-11 rounded-full" disabled={connectRecording.isPending || editorBusy || entries.isError} onClick={() => { const record = recorded.find((item) => item.id === mediaScope.id); if (record) connectRecording.mutate(record); }}>Start writing for this recording</Button><Button variant="ghost" className="h-11" disabled={editorBusy || create.isPending || entries.isError} onClick={() => create.mutate("general")}>Create a separate note</Button></div>}
        {!!selectedIds.length && <Button variant="ghost" className="my-3 h-11 text-xs" disabled={editorBusy || selectedIds.length >= 8} onClick={() => { if (canSwitch()) { setSelecting(true); setArchiveOpen(true); } }}>Add another meeting note from archive</Button>}
        <div id="notebook-jasper" hidden={selectedIds.length < 2}><NotebookQuestions ownerId={userId} documents={picked} disabled={editorBusy || picked.length !== selectedIds.length || selectedMissing || !showFocus} /></div>
        {!selectedIds.length && !mediaScope && <div className="flex min-h-96 flex-col justify-center px-6"><FileText className="mb-6 h-8 w-8 text-[#F22659]" /><h2 className="font-serif text-4xl">Room for your next thought.</h2><p className="mt-4 max-w-sm text-sm leading-relaxed text-muted-foreground">Open a note to focus. Select a few to connect ideas, compare decisions or draft what comes next.</p></div>}
        {requested && entries.data && !entries.data.some((note) => note.id === requested) && !recorded.some((record) => record.id === requested) && <p role="status" className="py-3 text-sm text-muted-foreground">This entry isn't available here yet. Check private sync, load older recordings, or use the browser where you recorded.</p>}
      </article>
    </div>
    {selectedIds.length > 1 && <div className="sticky bottom-4 z-10 mt-4 flex justify-end pb-[env(safe-area-inset-bottom)]"><Button className="h-12 max-w-full rounded-full bg-foreground px-6 text-background shadow-lg hover:bg-foreground/90" onClick={() => { if (!canSwitch()) return; setShowFocus(true); requestAnimationFrame(() => document.getElementById("notebook-jasper")?.scrollIntoView({ behavior: "smooth", block: "start" })); }}>Jasper · {selectedIds.length} selected notes</Button></div>}
    <AlertDialog open={!!deletion} onOpenChange={(open) => { if (!open && !remove.isPending) setDeletion(null); }}><AlertDialogContent><AlertDialogHeader><AlertDialogTitle>Delete this note?</AlertDialogTitle><AlertDialogDescription>Its writing and follow-ups will be removed here. Synced deletion reaches your other devices. Recordings and exported copies are not deleted.</AlertDialogDescription></AlertDialogHeader><AlertDialogFooter><AlertDialogCancel disabled={remove.isPending}>Cancel</AlertDialogCancel><AlertDialogAction disabled={remove.isPending || editorBusy} onClick={(event) => { event.preventDefault(); if (deletion) remove.mutate(deletion); }}>Delete note</AlertDialogAction></AlertDialogFooter></AlertDialogContent></AlertDialog>
  </section>;
}
