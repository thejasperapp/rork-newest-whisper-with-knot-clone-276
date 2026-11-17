import { useEffect, useMemo, useRef, useState } from "react";
import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Cloud, MoreHorizontal, Play, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { useSearchParams } from "react-router-dom";
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog";
import { listRecordingArchivePage, recordingPlaybackURL, deleteRecordingArchive, type RecordingArchive } from "@/lib/recordingCloud";
import { recordingTime } from "@/lib/meetingRecordingModel";
import { ensureRecordingNote } from "@/lib/recordingNotebook";
import { recordingTranscriptText } from "@/lib/recordingNotebookText";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";
import { RecordingCloudBackupButton } from "./RecordingCloudBackupButton";
import { RecordingTranscriptTimeline } from './RecordingTranscriptTimeline';
import { JasperMeetingAssistant } from './JasperMeetingAssistant';
import type { JasperRecordingContext } from '@/lib/jasperMeetings';

/** Private snapshots are visibly distinct from browser files and shared meeting recaps. */
export function CloudRecordingLibrary({ ownerId, meetingId = null }: { ownerId: string; meetingId?: string | null }): JSX.Element {
  const [selected, setSelected] = useState<string | null>(null);
  const [search, setSearch] = useState<string>("");
  const archives = useInfiniteQuery({ queryKey: ["recording-cloud", ownerId, meetingId], initialPageParam: undefined as string | undefined, queryFn: ({ signal, pageParam }) => listRecordingArchivePage(ownerId, signal, pageParam, meetingId), getNextPageParam: (last) => last.nextCursor, gcTime: 0 });
  const items = useMemo(() => (archives.data?.pages.flatMap((page) => page.items) ?? []).filter((row) => `${row.snapshot.title} ${row.snapshot.transcript.map((p) => p.text).join(" ")} ${row.snapshot.markers.map((m) => m.title).join(" ")}`.toLowerCase().includes(search.toLowerCase())), [archives.data, search]);
  return <section className="space-y-4 border-t border-border pt-8">
    <div><h3 className="flex items-center gap-2 text-xl font-semibold"><Cloud className="h-5 w-5" />{meetingId ? "This meeting’s cloud backups" : "Private cloud backups"}</h3><p className="mt-2 text-sm text-muted-foreground">Snapshots you explicitly backed up. Available to the same Whisper account across browsers and iPhone. These are separate from private notes and shared meeting recaps.</p></div>
    <input aria-label="Search loaded cloud backups" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search loaded backups…" className="min-h-11 w-full rounded-xl border border-border bg-background px-3 text-sm" />
    {archives.isPending && <p className="text-sm text-muted-foreground">Opening your private archive…</p>}
    {archives.isPaused && <p className="text-sm text-muted-foreground">Cloud backups need a connection. Browser recordings above still work offline once the app is open.</p>}
    {archives.error && <p role="alert" className="text-sm">Couldn’t load cloud backups. <Button variant="ghost" onClick={() => void archives.refetch()}>Try again</Button></p>}
    {archives.data && !items.length && <p className="py-3 text-sm text-muted-foreground">{search ? "No match in the loaded backups." : "No cloud backups yet. Open a browser recording and choose Save private cloud snapshot if everyone approved cloud storage."}</p>}
    <div className="divide-y divide-border">{items.map((row) => <div key={row.id}><button type="button" aria-expanded={selected === row.id} onClick={() => setSelected(selected === row.id ? null : row.id)} className="flex min-h-20 w-full items-center gap-3 py-3 text-left"><span className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-muted"><Play className="h-4 w-4" /></span><span className="min-w-0"><span className="block truncate font-medium">{row.snapshot.title || "Meeting recording"}</span><span className="text-xs text-muted-foreground">{new Date(row.created_at).toLocaleString()} · {recordingTime(row.snapshot.duration)} · {row.state === "ready" ? "Backed up" : row.state === "deleting" ? "Deletion incomplete · retry" : "Upload incomplete · resume from original browser"}</span></span></button>{selected === row.id && row.owner_id === ownerId && <CloudRecordingPlayer key={row.id} archive={row} onClose={() => setSelected(null)} />}</div>)}</div>
    <div className="flex gap-2"><Button variant="ghost" onClick={() => void archives.refetch()} disabled={archives.isFetching}>Refresh backups</Button>{archives.hasNextPage && <Button variant="outline" disabled={archives.isFetchingNextPage} onClick={() => void archives.fetchNextPage()}>Load older backups</Button>}</div>
  </section>;
}

/** Inline playback keeps the note and its source on the same page. */
export function CloudRecordingPlayer({ archive, onClose, onImportTranscript, embedded = false }: { archive: RecordingArchive; onClose: () => void; onImportTranscript?: (text: string) => void; embedded?: boolean }): JSX.Element {
  const [, setParams] = useSearchParams();
  const record = archive.snapshot; const begin = useChatOperationGuard(archive.owner_id, archive.id); const queryClient = useQueryClient();
  const video = useRef<HTMLVideoElement | null>(null); const controller = useRef<AbortController | null>(null);
  const [audioOnly, setAudioOnly] = useState<boolean>(false), [confirmDelete, setConfirmDelete] = useState<boolean>(false), [playError, setPlayError] = useState<boolean>(false);
  const [toolsOpen, setToolsOpen] = useState<boolean>(false);
  const [position, setPosition] = useState<number>(0);
  const [jasperContext, setJasperContext] = useState<JasperRecordingContext | null>(null);
  const pendingSeek = useRef<{ position: number; play: boolean } | null>(null);
  const playback = useQuery({ queryKey: ["recording-cloud-playback", archive.owner_id, archive.id, audioOnly], queryFn: ({ signal }) => recordingPlaybackURL(archive, audioOnly, signal), enabled: archive.state === "ready", gcTime: 0, staleTime: Infinity, refetchOnWindowFocus: false, refetchOnReconnect: false });
  useEffect(() => () => { controller.current?.abort(); }, []);
  const action = useMutation({ networkMode: "always", mutationFn: async ({ kind, check, abort }: { kind: "delete" | "notebook"; check: () => void; abort: AbortController }) => {
    check(); abort.signal.throwIfAborted();
    if (kind === "delete") { video.current?.pause(); await deleteRecordingArchive(archive, abort.signal, check); check(); onClose(); }
    else {
      const note = await ensureRecordingNote(record, check); check();
      void queryClient.invalidateQueries({ queryKey: ["personal-notebook", archive.owner_id] });
      setParams((previous) => { const next = new URLSearchParams(previous); next.set("note", note.id); next.delete("recording"); return next; });
      toast.success("Recording linked to its note. Existing writing is unchanged."); onClose();
    }
    void queryClient.invalidateQueries({ queryKey: ["recording-cloud", archive.owner_id] });
  }, onSettled: () => { controller.current = null; }, onError: (error) => { toast.error(error instanceof Error ? error.message : "That action failed. Refresh and try again."); void queryClient.invalidateQueries({ queryKey: ["recording-cloud", archive.owner_id] }); } });
  const perform = (kind: "delete" | "notebook"): void => { if (controller.current) return; const check = begin(); const abort = new AbortController(); controller.current = abort; action.mutate({ kind, check, abort }); };
  const applySeek = (): void => { const element = video.current, pending = pendingSeek.current; if (!element || !pending || element.readyState < 1) return; const end = Number.isFinite(element.duration) ? Math.min(record.duration, element.duration) : record.duration; element.currentTime = Math.max(0, Math.min(end, pending.position)); setPosition(element.currentTime); pendingSeek.current = null; if (pending.play) void element.play().catch(() => setPlayError(true)); };
  const seek = (seconds: number): void => { if (!Number.isFinite(seconds)) return; pendingSeek.current = { position: seconds, play: true }; applySeek(); };
  return <section aria-label="Cloud recording playback" className={embedded ? "min-w-0 space-y-3" : "min-w-0 space-y-4 rounded-2xl border border-border p-4"}>{!embedded && <header className="flex items-center justify-between gap-3"><h3 className="text-sm font-semibold">Cloud recording · {recordingTime(record.duration)}</h3><Button variant="ghost" className="h-11 text-xs" onClick={onClose}>Hide player</Button></header>}
    {archive.state === "ready" ? <>
      {playback.isPending && <p className="text-sm">Opening private playback…</p>}
      {playback.data && !playback.error && <video ref={video} src={playback.data} controls playsInline preload="metadata" className={!audioOnly && record.mimeType.startsWith("video") ? "aspect-video w-full rounded-2xl bg-black object-contain" : "h-16 w-full rounded-xl bg-muted"} onLoadedMetadata={applySeek} onTimeUpdate={() => { if (!pendingSeek.current) setPosition(video.current?.currentTime ?? 0); }} onError={() => setPlayError(true)} />}
      {(playError || playback.error) && <p role="alert" className="text-sm">Couldn’t play this file. Try the continuous audio version, or reopen playback. <Button variant="ghost" onClick={() => { setPlayError(false); void playback.refetch().then((result) => { if (!result.error) video.current?.load(); }); }}>Reopen playback</Button></p>}
      {embedded && <div className="flex min-h-11 items-center justify-between gap-2"><span className="text-xs text-muted-foreground">{recordingTime(record.duration)} · Private cloud backup</span><Button variant="ghost" size="icon" aria-label="Recording options" aria-expanded={toolsOpen} className="h-11 w-11" onClick={() => setToolsOpen((value) => !value)}><MoreHorizontal className="h-5 w-5" /></Button></div>}
      <RecordingTranscriptTimeline passages={record.transcript} position={position} onSeek={seek} onAsk={record.meetingId && record.cloudConsent ? (passages) => setJasperContext({ id: record.id, title: record.title, revision: record.revision, passages: structuredClone(passages) }) : undefined} />
      {jasperContext && record.meetingId && <div className="rounded-2xl border border-border p-4"><Button variant="ghost" className="mb-3 h-11 text-xs" onClick={() => setJasperContext(null)}>Close recording sidekick</Button><JasperMeetingAssistant key={`${record.id}:${jasperContext.revision}:${jasperContext.passages[0]?.id}`} owner={archive.owner_id} meetingID={record.meetingId} recordingContext={jasperContext} onSeekRecording={(id, seconds) => { if (id === record.id) seek(seconds); }} /></div>}
      <div hidden={embedded && !toolsOpen} className="space-y-4">
      <div className="flex flex-wrap gap-2"><Button variant="outline" onClick={() => { pendingSeek.current = { position: video.current?.currentTime ?? position, play: video.current ? !video.current.paused : false }; setAudioOnly((value) => !value); setPlayError(false); }}>{audioOnly ? "Original recording" : "Continuous audio"}</Button>{onImportTranscript ? <Button variant="outline" disabled={action.isPending || !record.transcript.length} onClick={() => { try { begin()(); onImportTranscript(recordingTranscriptText(record.transcript)); } catch (error) { toast.error((error as Error).message); } }}>Use transcript in this note</Button> : !embedded ? <Button variant="outline" disabled={action.isPending} onClick={() => perform("notebook")}>Open linked note</Button> : null}</div>
      {record.warnings.map((warning, index) => <p key={index} className="text-xs text-muted-foreground">{warning}</p>)}
      <details><summary className="min-h-11 cursor-pointer py-3 text-sm font-semibold">Transcript, decisions & bookmarks</summary><h4 className="font-semibold">Reviewed decisions & bookmarks</h4><div className="space-y-1">{record.markers.filter((marker) => marker.reviewed).map((marker) => <button key={marker.id} type="button" className="block min-h-11 w-full rounded-xl bg-muted p-3 text-left text-sm" onClick={() => seek(marker.seconds)}><span className="mr-2 text-xs font-semibold">{recordingTime(marker.seconds)}</span>{marker.title}</button>)}</div>
      <h4 className="font-semibold">Transcript · tap to listen</h4><div className="max-h-96 space-y-2 overflow-y-auto">{record.transcript.map((passage) => <button key={passage.id} type="button" className={`block min-h-11 w-full rounded-xl p-3 text-left ${position >= passage.start && position < passage.end ? "bg-muted" : ""}`} onClick={() => seek(passage.start)}><span className="text-xs font-semibold">{recordingTime(passage.start)}–{recordingTime(passage.end)}{passage.timing === "chunk" ? " · Approx." : ""}</span><p className="mt-1 whitespace-pre-wrap text-sm leading-relaxed">{passage.text}</p></button>)}</div>
    </details></div></> : <><p className="text-sm">{archive.state === "uploading" ? "This backup is not complete. Resume with the same account on the browser where you recorded, or delete the incomplete cloud copy." : "Deletion needs to finish. Try Delete cloud backup again; local files are unaffected."}</p>{archive.state === "uploading" && <RecordingCloudBackupButton record={record} resume />}</>}
    <div hidden={embedded && !toolsOpen && archive.state === "ready"} className="space-y-3"><p className="text-xs text-muted-foreground">Private snapshot · {new Date(archive.created_at).toLocaleString()}</p>
    <Button variant="ghost" disabled={action.isPending} onClick={() => setConfirmDelete(true)}><Trash2 className="mr-2 h-4 w-4" />Delete cloud backup</Button>
    <p className="text-xs text-muted-foreground">Playback uses a temporary access link. Don’t share that link. Deleting a cloud snapshot does not delete device notes, local recordings or exports.</p></div>
    <AlertDialog open={confirmDelete} onOpenChange={setConfirmDelete}><AlertDialogContent portalContainer={document.fullscreenElement as HTMLElement | null} overlayClassName="z-[100]" className="z-[110]"><AlertDialogHeader><AlertDialogTitle>Delete this cloud backup?</AlertDialogTitle><AlertDialogDescription>Its cloud audio, video, transcript and markers will be removed. Local recordings, other snapshots, Notebook copies and exports are kept.</AlertDialogDescription></AlertDialogHeader><AlertDialogFooter><AlertDialogCancel>Keep backup</AlertDialogCancel><AlertDialogAction onClick={() => perform("delete")}>Delete cloud backup</AlertDialogAction></AlertDialogFooter></AlertDialogContent></AlertDialog>
  </section>;
}
