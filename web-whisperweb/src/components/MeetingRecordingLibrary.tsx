import { useEffect, useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { BookmarkPlus, Download, MoreHorizontal, Play, Sparkles, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { CloudRecordingLibrary } from "./CloudRecordingLibrary";
import { RecordingCloudBackupButton } from "./RecordingCloudBackupButton";
import { Button } from "@/components/ui/button";
import { useSearchParams } from "react-router-dom";
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";
import { deleteRecording, editRecording, listRecordings, recordingChunks } from "@/lib/meetingRecordingStorage";
import { recordingTime, type MeetingRecording, type RecordingMarker } from "@/lib/meetingRecordingModel";
import { recordingMedia } from "@/lib/recordingMedia";
import { recordingAudioBackup } from "@/lib/recordingAudioBackup";
import { retryRecordingTranscription } from "@/lib/recordingTranscription";
import { proposeRecordingDecisions } from "@/lib/recordingIntelligence";
import { ensureRecordingNote } from "@/lib/recordingNotebook";
import { recordingTranscriptText } from "@/lib/recordingNotebookText";
import { RecordingTranscriptTimeline } from './RecordingTranscriptTimeline';
import { JasperMeetingAssistant } from './JasperMeetingAssistant';
import type { JasperRecordingContext } from '@/lib/jasperMeetings';

const inputClass = "min-h-11 rounded-xl border border-border bg-background px-3 py-2 text-sm";
function download(blob: Blob, name: string): void { const url = URL.createObjectURL(blob); const link = document.createElement("a"); link.href = url; link.download = name; link.click(); setTimeout(() => URL.revokeObjectURL(url), 60000); }

/** Same-origin, account-local recording archive. Does not expose any shared meeting rows. */
export function MeetingRecordingLibrary({ ownerId, meetingId = null }: { ownerId: string; meetingId?: string | null }): JSX.Element {
  const [selected, setSelected] = useState<string | null>(null);
  const [search, setSearch] = useState<string>("");
  const records = useQuery({ queryKey: ["recordings", ownerId], queryFn: () => listRecordings(ownerId), refetchInterval: 5000, networkMode: "always" });
  const items = useMemo(() => (records.data ?? []).filter((record) => (!meetingId || record.meetingId === meetingId) && `${record.title} ${record.transcript.map((p) => p.text).join(" ")} ${record.markers.map((m) => m.title).join(" ")}`.toLowerCase().includes(search.toLowerCase())), [records.data, search, meetingId]);
  const record = records.data?.find((item) => item.id === selected && (!meetingId || item.meetingId === meetingId));
  return <section aria-label="Meeting recordings" className="mx-auto w-full max-w-6xl space-y-4 border-t border-border py-6">
    <div><p className="text-xs font-semibold uppercase tracking-[0.18em] text-muted-foreground">Meeting memory</p><h2 className="mt-1 text-2xl font-semibold tracking-tight">{meetingId ? "Recordings for this meeting" : "Recordings"}</h2><p className="mt-2 max-w-2xl text-sm text-muted-foreground">Saved audio, timed transcripts and reviewed decisions. Browser recordings below stay on this account and website address. Explicitly approved cloud snapshots appear separately and can open on your other devices. Export or confirm a cloud backup before clearing browser data.</p></div>
    <input aria-label="Search recordings and transcripts" placeholder="Search recordings, transcripts, decisions…" className={`${inputClass} w-full`} value={search} onChange={(e) => setSearch(e.target.value)} />
    {records.isPending && <p className="text-sm text-muted-foreground">Opening this browser’s recordings…</p>}
    {records.error && <div role="alert" className="text-sm">Couldn’t open recordings. Nothing has been deleted. <Button variant="ghost" onClick={() => void records.refetch()}>Try again</Button></div>}
    {selected && records.data && !record && <p role="alert" className="rounded-xl border border-border p-4 text-sm">This recording isn't in this account's storage at this website address. Open the same address and browser used to record, or look for an explicitly saved cloud backup below. Nothing has been removed by opening this link.</p>}
    {records.data && !items.length && <div className="rounded-2xl border border-dashed border-border px-5 py-8"><p className="font-medium">{search ? "No matching recordings" : "Keep the conversation, not just the recap."}</p><p className="mt-2 text-sm text-muted-foreground">{search ? "Try a different phrase." : "In a Whisper web meeting, the signed-in host can choose Activities → Recording. Everyone must allow it first. You can record audio or add video, and optionally let Jasper listen."}</p></div>}
    <div className="divide-y divide-border">{items.map((item) => <div key={item.id}><button type="button" className="flex min-h-20 w-full items-center gap-4 py-4 text-left" aria-expanded={selected === item.id} onClick={() => setSelected(selected === item.id ? null : item.id)}><span className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-foreground text-background"><Play className="h-4 w-4" /></span><span className="min-w-0 flex-1"><span className="block truncate font-medium">{item.title || "Meeting recording"}</span><span className="text-xs text-muted-foreground">{new Date(item.createdAt).toLocaleDateString()} · {recordingTime(item.duration)} · {item.mimeType.startsWith("video") ? "Video + audio" : "Audio"} · {item.status === "recording" ? "Recording / not finalized" : item.status === "interrupted" ? "Interrupted · saved parts" : "Saved"}</span></span><span className="text-xs text-muted-foreground">{item.markers.filter((m) => m.kind === "decision" && m.reviewed).length} decisions</span></button>{record?.id === item.id && <RecordingPlayer key={`${ownerId}:${record.id}`} record={record} onClose={() => setSelected(null)} />}</div>)}</div>
    <CloudRecordingLibrary key={`${ownerId}:${meetingId ?? "all"}`} ownerId={ownerId} meetingId={meetingId} />
  </section>;
}

/** Reuses the actual recording player inline, without covering the note. */
export function RecordingPlayer({ record, onClose, onImportTranscript, embedded = false }: { record: MeetingRecording; onClose: () => void; onImportTranscript?: (text: string) => void; embedded?: boolean }): JSX.Element {
  const [, setParams] = useSearchParams();
  const queryClient = useQueryClient();
  const begin = useChatOperationGuard(record.ownerId, record.id);
  const media = useRef<HTMLVideoElement | null>(null);
  const controller = useRef<AbortController | null>(null);
  const [url, setURL] = useState<string | null>(null);
  const [position, setPosition] = useState<number>(0);
  const [title, setTitle] = useState<string>("");
  const [kind, setKind] = useState<"bookmark" | "decision">("bookmark");
  const [sourceIds, setSourceIds] = useState<string[]>([]);
  const [proposal, setProposal] = useState<RecordingMarker | null>(null);
  const [drafts, setDrafts] = useState<RecordingMarker[]>([]);
  const [windowStart, setWindowStart] = useState<string>("0");
  const [confirm, setConfirm] = useState<"delete" | "retry" | "analyze" | "recover" | null>(null);
  const [playError, setPlayError] = useState<string | null>(null);
  const [toolsOpen, setToolsOpen] = useState<boolean>(false);
  const [useAudio, setUseAudio] = useState<boolean>(false);
  const [jasperContext, setJasperContext] = useState<JasperRecordingContext | null>(null);
  const pendingSeek = useRef<{ position: number; play: boolean } | null>(null);
  const saved = record.status !== "recording";
  const chunks = useQuery({ queryKey: ["recording-media", record.ownerId, record.id, saved], queryFn: () => recordingChunks(record.ownerId, record.id), enabled: saved, gcTime: 0, networkMode: "always", staleTime: Infinity, refetchOnReconnect: false, refetchOnWindowFocus: false });
  const assembled = useQuery({ queryKey: ["recording-container", record.ownerId, record.id, saved], queryFn: () => recordingMedia(record, chunks.data ?? []), enabled: saved && !!chunks.data, networkMode: "always", staleTime: Infinity, gcTime: 0, refetchOnWindowFocus: false, refetchOnReconnect: false });
  const mediaBlob = assembled.data;
  const audioBackup = useQuery({ queryKey: ["recording-audio-backup", record.ownerId, record.id, saved], queryFn: () => recordingAudioBackup(chunks.data ?? [], record.duration), enabled: saved && !!chunks.data, networkMode: "always", staleTime: Infinity, gcTime: 0, refetchOnWindowFocus: false, refetchOnReconnect: false });
  const playbackBlob = useAudio || !mediaBlob?.size ? audioBackup.data : mediaBlob;
  useEffect(() => { if (!playbackBlob?.size) return; const next = URL.createObjectURL(playbackBlob); setURL(next); return () => { URL.revokeObjectURL(next); setURL(null); }; }, [playbackBlob]);
  useEffect(() => () => { controller.current?.abort(); }, []);
  const refresh = (): void => { void queryClient.invalidateQueries({ queryKey: ["recordings", record.ownerId] }); };
  const operation = useMutation({ networkMode: "always", mutationFn: async (action: "retry" | "analyze" | "delete" | "recover" | "notebook") => {
    const assertCurrent = begin(); assertCurrent(); controller.current?.abort(); const abort = new AbortController(); controller.current = abort;
    if (action === "retry") { if (!record.cloudConsent) throw new Error("Cloud transcription was not included in the participants’ permission."); await retryRecordingTranscription(record.ownerId, record.id, abort.signal, assertCurrent); }
    if (action === "analyze") { const start = Number(windowStart) * 60; if (!Number.isFinite(start) || start < 0 || start >= record.duration) throw new Error("Choose a starting minute inside this recording."); const found = await proposeRecordingDecisions(record, start, start + 600, assertCurrent, abort.signal); assertCurrent(); setDrafts(found); if (!found.length) toast("No explicit decisions found in that window."); }
    if (action === "delete") { await deleteRecording(record.ownerId, record.id, assertCurrent); assertCurrent(); onClose(); }
    if (action === "recover") await editRecording(record.ownerId, record.id, (current) => { assertCurrent(); if (current.revision !== record.revision || Date.now() - current.lastWriteAt < 20000) throw new Error("Recording is still changing. Wait at least 20 seconds after closing the original tab."); return { ...current, status: "interrupted", warnings: [...current.warnings, "Recovered saved parts after an interrupted session. The final seconds or container footer may be missing."].slice(-100) }; });
    if (action === "notebook") {
      const note = await ensureRecordingNote(record, assertCurrent); assertCurrent();
      void queryClient.invalidateQueries({ queryKey: ["personal-notebook", record.ownerId] });
      setParams((previous) => { const next = new URLSearchParams(previous); next.set("note", note.id); next.delete("recording"); return next; });
      toast.success("Recording linked to its note. Existing writing is unchanged."); onClose();
    }
    assertCurrent(); refresh();
  }, onError: (error) => toast.error(error instanceof Error ? error.message : "That action failed. Saved recording parts are retained.") });
  const marker = useMutation({ mutationFn: async (action: { remove?: string }) => {
    const assertCurrent = begin(); assertCurrent();
    const text = title.trim(); if (!action.remove && (!text || text.length > 300)) throw new Error("Add a title of up to 300 characters.");
    await editRecording(record.ownerId, record.id, (current) => { assertCurrent(); const next: RecordingMarker = { id: proposal?.id ?? crypto.randomUUID(), title: text, seconds: proposal?.seconds ?? position, kind, sourceIds, reviewed: true }; return { ...current, markers: action.remove ? current.markers.filter((m) => m.id !== action.remove) : [...current.markers.filter((m) => m.id !== next.id), next].sort((a, b) => a.seconds - b.seconds) }; }); assertCurrent();
  }, onSuccess: () => { setTitle(""); if (proposal) setDrafts((all) => all.filter((d) => d.id !== proposal.id)); setProposal(null); setSourceIds([]); refresh(); }, onError: () => toast.error("Couldn’t save the marker. Keep this window open and try again.") });
  const applySeek = (): void => { const element = media.current, pending = pendingSeek.current; if (!element || !pending || element.readyState < 1) return; const end = Number.isFinite(element.duration) ? Math.min(record.duration, element.duration) : record.duration; element.currentTime = Math.max(0, Math.min(end, pending.position)); setPosition(element.currentTime); pendingSeek.current = null; if (pending.play) void element.play().catch(() => setPlayError('Press Play to hear this moment.')); };
  const seek = (seconds: number): void => { if (!Number.isFinite(seconds)) return; pendingSeek.current = { position: seconds, play: true }; applySeek(); };
  const busy = operation.isPending || marker.isPending;
  return <section aria-label="Recording playback" className={embedded ? "min-w-0 space-y-3" : "min-w-0 space-y-4 rounded-2xl border border-border p-4"}>{!embedded && <header className="flex items-center justify-between gap-3"><h3 className="text-sm font-semibold">Recording · {recordingTime(record.duration)}</h3><Button variant="ghost" className="h-11 text-xs" onClick={onClose}>Hide player</Button></header>}
    {!saved && <div className="rounded-xl border border-border p-4 text-sm"><p>This recording is active or was not finalized. Stop it in the original meeting tab before opening playback.</p><Button variant="outline" className="mt-3 min-h-11" disabled={busy} onClick={() => setConfirm("recover")}>Original tab closed? Recover saved parts</Button></div>}
    {chunks.isPending && saved && <p className="text-sm">Opening saved media…</p>}
    {chunks.error && <p role="alert" className="text-sm">Couldn’t read the saved recording. <Button variant="ghost" onClick={() => void chunks.refetch()}>Retry</Button></p>}
    {url && <video ref={media} src={url} controls playsInline preload="metadata" className={!useAudio && record.mimeType.startsWith("video") ? "aspect-video w-full rounded-2xl bg-black object-contain" : "h-16 w-full rounded-xl bg-muted"} onLoadedMetadata={applySeek} onTimeUpdate={() => { if (!pendingSeek.current) setPosition(media.current?.currentTime ?? 0); }} onError={() => setPlayError("This browser couldn’t play the saved container. Export it and try a compatible player; interrupted recordings may have a missing ending.")} />}
    {saved && mediaBlob && !mediaBlob.size && <p role="alert" className="text-sm">No playable container was saved. Transcript audio, if present, can still be exported below.</p>}
    {assembled.error && <p role="alert" className="text-xs text-muted-foreground">Couldn’t prepare the original container. Open recording options for the audio backup; saved pieces have not been changed.</p>}
    {playError && <p role="status" className="text-sm text-muted-foreground">{playError} Open recording options for the audio backup.</p>}
    {embedded && <div className="flex min-h-11 items-center justify-between gap-2"><span className="text-xs text-muted-foreground">{recordingTime(record.duration)} · Private · This browser</span><Button variant="ghost" size="icon" aria-label="Recording options" aria-expanded={toolsOpen} className="h-11 w-11" onClick={() => setToolsOpen((value) => !value)}><MoreHorizontal className="h-5 w-5" /></Button></div>}
    {record.transcriptionState === 'pending' && <p role="status" className="text-xs text-muted-foreground">Recording saved. Its transcript is finishing in this browser; keep the tab open.</p>}
    {record.transcriptionState === 'incomplete' && <p role="status" className="text-xs text-muted-foreground">Some recording speech needs retry. Your timed audio is retained.<Button variant="link" className="min-h-11 text-xs" onClick={() => setConfirm('retry')}>Retry missing speech</Button></p>}
    {saved && <RecordingTranscriptTimeline passages={record.transcript} position={position} onSeek={seek} onAsk={record.meetingId && record.cloudConsent ? (passages) => setJasperContext({ id: record.id, title: record.title, revision: record.revision, passages: structuredClone(passages) }) : undefined} />}
    {jasperContext && record.meetingId && <div className="rounded-2xl border border-border p-4"><Button variant="ghost" className="mb-3 h-11 text-xs" onClick={() => setJasperContext(null)}>Close recording sidekick</Button><JasperMeetingAssistant key={`${record.id}:${jasperContext.revision}:${jasperContext.passages[0]?.id}`} owner={record.ownerId} meetingID={record.meetingId} recordingContext={jasperContext} onSeekRecording={(id, seconds) => { if (id === record.id) seek(seconds); }} /></div>}
    <div hidden={embedded && !toolsOpen} className="space-y-4">
    <details><summary className="min-h-11 cursor-pointer py-3 text-xs text-muted-foreground">Recording coverage & storage</summary><p className="py-3 text-xs text-muted-foreground">{record.coverage}</p></details>
    {audioBackup.data && <div className="flex flex-wrap items-center gap-2"><Button variant="outline" onClick={() => { pendingSeek.current = { position: media.current?.currentTime ?? position, play: media.current ? !media.current.paused : false }; if (!mediaBlob?.size) applySeek(); setUseAudio((value) => !value); setPlayError(null); }}>{useAudio ? "Use original recording" : "Play continuous audio backup"}</Button><Button variant="ghost" onClick={() => audioBackup.data && download(audioBackup.data, `audio-${record.id}.wav`)}>Export continuous WAV</Button><p className="text-xs text-muted-foreground">Keeps the original timing; any missing audio remains a silent gap.</p></div>}
    {audioBackup.error && <p role="alert" className="text-xs text-muted-foreground">Couldn’t assemble audio backup. The individual pieces below are retained.</p>}
    {record.warnings.map((warning, index) => <p key={`${index}:${warning}`} className="text-xs text-muted-foreground">{warning}</p>)}
    <div className="flex flex-wrap gap-2">
      <Button variant="outline" disabled={!mediaBlob?.size} onClick={() => mediaBlob && download(mediaBlob, `meeting-${record.id}.${record.mimeType.includes("mp4") ? "mp4" : "webm"}`)}><Download className="mr-2 h-4 w-4" />Export recording</Button>
      <Button variant="outline" onClick={() => download(new Blob([`# ${record.title}\n\n${record.coverage}\n\n## Transcript\n${record.transcript.map((p) => `[${recordingTime(p.start)}–${recordingTime(p.end)}; ${p.timing === "chunk" ? "approximate chunk range" : "speech timing"}] ${p.speakerName ? `${p.speakerName}: ` : ''}${p.text}`).join("\n")}\n\n## Reviewed markers\n${record.markers.filter((m) => m.reviewed).map((m) => `[${recordingTime(m.seconds)}] ${m.kind}: ${m.title} [${m.sourceIds.join(", ")}]`).join("\n")}`], { type: "text/markdown" }), `meeting-${record.id}.md`)}>Export transcript</Button>
      {onImportTranscript ? <Button variant="outline" disabled={busy || !saved || !record.transcript.length} onClick={() => { try { begin()(); onImportTranscript(recordingTranscriptText(record.transcript)); } catch (error) { toast.error((error as Error).message); } }}>Use transcript in this note</Button> : !embedded ? <Button variant="outline" disabled={busy || !saved} onClick={() => operation.mutate("notebook")}>Open linked note</Button> : null}
      <Button variant="ghost" disabled={busy || !saved} onClick={() => setConfirm("delete")}><Trash2 className="mr-2 h-4 w-4" />Delete</Button>
    </div>
    <RecordingCloudBackupButton record={record} disabled={busy || !saved} />
    <details><summary className="min-h-11 cursor-pointer py-3 text-sm font-semibold">Transcript, decisions & bookmarks</summary><div className="grid gap-6 pt-3">
      <section className="min-w-0 space-y-3"><h3 className="font-semibold">Transcript · tap a time to listen</h3><p className="text-xs text-muted-foreground">Times are relative to recording start, not meeting arrival. “Approx.” means the service returned only a chunk range—not exact sentence timing. Speaker names are not inferred.</p>
        <Button variant="outline" disabled={busy || !saved || !record.cloudConsent} onClick={() => setConfirm("retry")}>{operation.isPending ? "Working…" : "Transcribe missing audio"}</Button>
        {operation.isPending && <Button variant="ghost" onClick={() => controller.current?.abort()}>Stop AI</Button>}
        {!record.cloudConsent && <p className="text-xs text-muted-foreground">Cloud AI was not included in this recording’s permission.</p>}
        <div className="max-h-[26rem] space-y-1 overflow-y-auto">{record.transcript.map((p) => <article key={p.id} className={`rounded-xl border p-3 ${position >= p.start && position < p.end ? "border-foreground/25 bg-muted" : "border-transparent"}`}><button type="button" className="min-h-11 text-xs font-semibold tabular-nums" onClick={() => seek(p.start)}>{recordingTime(p.start)}–{recordingTime(p.end)}{p.timing === "chunk" ? " · Approx." : ""}</button><p className="whitespace-pre-wrap text-sm leading-relaxed">{p.text}</p><Button variant="ghost" className="mt-1 min-h-11 text-xs" disabled={!saved || busy} onClick={() => { setKind("decision"); setSourceIds([p.id]); setPosition(p.start); setProposal({ id: crypto.randomUUID(), title: "", seconds: p.start, kind: "decision", sourceIds: [p.id], reviewed: false }); setTitle(""); seek(p.start); }}>Mark decision here</Button></article>)}</div>
        {!record.transcript.length && <p className="py-5 text-sm text-muted-foreground">No transcript yet. Audio stays saved even if transcription fails.</p>}
        {saved && <details className="text-xs text-muted-foreground"><summary className="min-h-11 cursor-pointer py-3">Backup audio pieces ({chunks.data?.filter((c) => c.kind === "audio").length ?? 0})</summary><p className="pb-2">Independently playable WAV pieces for recovery if the main container cannot play.</p><div className="flex max-h-32 flex-wrap gap-2 overflow-y-auto">{chunks.data?.filter((c) => c.kind === "audio").map((c) => <Button variant="outline" key={c.key} onClick={() => download(c.blob, `audio-${c.index}-${record.id}.wav`)}>{recordingTime(c.start)}</Button>)}</div></details>}
      </section>
      <section className="min-w-0 space-y-4"><h3 className="font-semibold">Decisions & bookmarks</h3><p className="text-xs text-muted-foreground">Review the wording and listen to the evidence. A marker opens the source moment, not a time invented by Jasper.</p>
        <div className="space-y-2">{record.markers.map((m) => <div key={m.id} className="flex items-start gap-2 border-b border-border py-2"><button type="button" className="min-h-11 flex-1 text-left" onClick={() => seek(m.seconds)}><span className="text-xs font-semibold">{recordingTime(m.seconds)} · {m.kind === "decision" ? "Reviewed decision" : "Bookmark"}</span><p className="mt-1 text-sm">{m.title}</p></button><Button size="icon" variant="ghost" aria-label="Delete marker" disabled={busy} onClick={() => marker.mutate({ remove: m.id })}><Trash2 className="h-4 w-4" /></Button></div>)}</div>
        <div className="space-y-2 rounded-2xl border border-border p-4"><p className="text-xs font-medium">{proposal ? "Review decision" : "Mark this moment"} · {recordingTime(proposal?.seconds ?? position)}</p><select aria-label="Marker type" value={kind} onChange={(e) => setKind(e.target.value as "bookmark" | "decision")} className={`${inputClass} w-full`}><option value="bookmark">Bookmark</option><option value="decision">Decision</option></select><textarea aria-label="Marker wording" maxLength={300} value={title} onChange={(e) => setTitle(e.target.value)} className={`${inputClass} min-h-24 w-full`} placeholder="What mattered here?" />{proposal?.sourceIds.map((id) => { const source = record.transcript.find((p) => p.id === id); return source ? <button type="button" key={id} onClick={() => seek(source.start)} className="block min-h-11 text-left text-xs text-muted-foreground">[{recordingTime(source.start)}] {source.text}</button> : null; })}<Button disabled={!saved || busy || !title.trim()} className="min-h-11 rounded-full" onClick={() => marker.mutate({})}><BookmarkPlus className="mr-2 h-4 w-4" />{kind === "decision" ? "Save reviewed decision" : "Save bookmark"}</Button>{proposal && <Button variant="ghost" onClick={() => { setProposal(null); setSourceIds([]); setTitle(""); }}>Cancel review</Button>}</div>
        <div className="space-y-3 border-t border-border pt-4"><div className="flex items-center gap-2"><Sparkles className="h-4 w-4 text-orange-500" /><h4 className="text-sm font-semibold">Ask Jasper for decisions</h4></div><p className="text-xs text-muted-foreground">Analyze a ten-minute window, then review each suggestion. Long or dense windows may need a shorter Notebook excerpt. Nothing is automatically marked as a decision.</p><label className="flex items-center gap-2 text-sm">Starting minute <input type="number" min={0} max={Math.floor(record.duration / 60)} value={windowStart} onChange={(e) => setWindowStart(e.target.value)} className={`${inputClass} w-24`} /></label><Button variant="outline" disabled={!saved || busy || !record.cloudConsent || !record.transcript.length} onClick={() => setConfirm("analyze")}>Find decisions in this window</Button>
          {drafts.map((draft) => <div key={draft.id} className="space-y-2 rounded-xl bg-muted p-3"><p className="text-xs font-semibold">Unreviewed suggestion · {recordingTime(draft.seconds)}</p><p className="text-sm">{draft.title}</p><Button variant="outline" className="min-h-11" onClick={() => { setProposal(draft); setSourceIds(draft.sourceIds); setTitle(draft.title); setKind("decision"); seek(draft.seconds); }}>Listen & review</Button><Button variant="ghost" onClick={() => setDrafts((all) => all.filter((d) => d.id !== draft.id))}>Dismiss</Button></div>)}
        </div>
      </section>
    </div></details>
    </div>
    <AlertDialog open={confirm !== null} onOpenChange={(open) => { if (!open) setConfirm(null); }}><AlertDialogContent portalContainer={document.fullscreenElement as HTMLElement | null} overlayClassName="z-[100]" className="z-[110]"><AlertDialogHeader><AlertDialogTitle>{confirm === "delete" ? "Delete this recording permanently?" : confirm === "recover" ? "Recover an interrupted recording?" : "Use cloud AI for this recording?"}</AlertDialogTitle><AlertDialogDescription>{confirm === "delete" ? "This removes the media, transcript and markers from this browser. Export anything you need first. Cloud backups, Notebook copies and downloaded files are not deleted." : confirm === "recover" ? "Only continue if the original recording tab is closed. Recovery keeps the parts already saved, but the last seconds or video ending may be missing. An active recording must be stopped in its own tab instead." : confirm === "retry" ? "Unprocessed saved audio is sent to Whisper’s cloud transcription provider. Audio stays saved if a request fails; successful pieces are not sent twice." : "The selected ten-minute transcript window is sent to Jasper. Decision suggestions can be wrong: review the original audio before saving any marker."}</AlertDialogDescription></AlertDialogHeader><AlertDialogFooter><AlertDialogCancel>Cancel</AlertDialogCancel><AlertDialogAction onClick={() => { if (confirm) operation.mutate(confirm); setConfirm(null); }}>{confirm === "delete" ? "Delete recording" : "Continue"}</AlertDialogAction></AlertDialogFooter></AlertDialogContent></AlertDialog>
  </section>;
}
