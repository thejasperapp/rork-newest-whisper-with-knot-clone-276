import { useEffect, useMemo, useState } from "react";
import { useInfiniteQuery, useQuery } from "@tanstack/react-query";
import { NotebookRecordingPassages } from "./NotebookRecordingPassages";
import { Button } from "./ui/button";
import { RecordingPlayer } from "./MeetingRecordingLibrary";
import { CloudRecordingPlayer } from "./CloudRecordingLibrary";
import { listRecordings } from "@/lib/meetingRecordingStorage";
import { listRecordingArchivePage, listRecordingArchives, type RecordingArchive } from "@/lib/recordingCloud";
import { recordingTime, type MeetingRecording } from "@/lib/meetingRecordingModel";
import type { NotebookDocument, NotebookSource } from "@/lib/notebookDocument";

type Source = { key: string; record: MeetingRecording; archive?: RecordingArchive; ready: boolean };

/** Shows the actual recording as soon as a note opens, without autoplay, upload or transcript ingestion. */
export function NotebookRecordingSources({ note, onImportTranscript, onRecordingChange, onAttach, onContext }: { onContext?: (context: { sources: NotebookSource[]; label: string }) => void; note: Pick<NotebookDocument, "id" | "ownerId" | "meetingId" | "recordingIds">; onImportTranscript?: (text: string) => void; onRecordingChange?: (record: MeetingRecording | null) => void; onAttach?: (record: MeetingRecording) => void }): JSX.Element {
  const attachmentKey = [...new Set([note.id, ...(note.recordingIds ?? [])])].join(",");
  const exactIds = useMemo(() => attachmentKey ? attachmentKey.split(",") : [], [attachmentKey]);
  const [selected, setSelected] = useState<string | null>(null);
  const local = useQuery({ queryKey: ["recordings", note.ownerId], queryFn: () => listRecordings(note.ownerId), networkMode: "always", refetchInterval: 5000 });
  const exactCloud = useQuery({ queryKey: ["recording-cloud", note.ownerId, "exact-note", note.id, attachmentKey], queryFn: async ({ signal }) => (await Promise.all(exactIds.map((id) => listRecordingArchives(note.ownerId, signal, undefined, null, id)))).flat(), gcTime: 0 });
  const cloud = useInfiniteQuery({ enabled: !!note.meetingId, queryKey: ["recording-cloud", note.ownerId, "note", note.id, note.meetingId], initialPageParam: undefined as string | undefined, queryFn: ({ signal, pageParam }) => listRecordingArchivePage(note.ownerId, signal, pageParam, note.meetingId), getNextPageParam: (page) => page.nextCursor, gcTime: 0 });
  const sources = useMemo<Source[]>(() => {
    const items: Source[] = [];
    for (const record of local.data ?? []) {
      if (record.ownerId === note.ownerId && (exactIds.includes(record.id) || (!!note.meetingId && record.meetingId === note.meetingId))) {
        items.push({ key: `local:${record.id}`, record, ready: record.status === "ready" });
      }
    }
    const seen = new Set<string>();
    for (const archive of [...(exactCloud.data ?? []), ...(cloud.data?.pages.flatMap((page) => page.items) ?? [])]) {
      if (seen.has(archive.id) || archive.owner_id !== note.ownerId || (!exactIds.includes(archive.recording_id) && (!note.meetingId || archive.snapshot.meetingId !== note.meetingId))) continue;
      seen.add(archive.id);
      items.push({ key: `cloud:${archive.id}`, record: archive.snapshot, archive, ready: archive.state === "ready" });
    }
    return items.sort((a, b) => Number(exactIds.includes(b.record.id)) - Number(exactIds.includes(a.record.id)) || Number(b.ready) - Number(a.ready) || Number(!!a.archive) - Number(!!b.archive));
  }, [local.data, exactCloud.data, cloud.data, exactIds, note.meetingId, note.ownerId]);
  const exactReady = sources.find((item) => exactIds.includes(item.record.id) && item.ready);
  const lookupSettled = !local.isPending && (!exactCloud.isPending || exactCloud.isPaused);
  const preferred = exactReady ?? (lookupSettled ? note.recordingIds?.length ? sources.find((item) => exactIds.includes(item.record.id)) : sources.find((item) => item.ready) ?? sources[0] : undefined);
  const active = sources.find((item) => item.key === selected) ?? preferred;
  useEffect(() => { if (active && active.key !== selected) setSelected(active.key); }, [active, selected]);
  useEffect(() => { onRecordingChange?.(active?.record ?? null); }, [active?.record, onRecordingChange]);
  const missingAttachments = note.recordingIds?.filter((id) => !sources.some((source) => source.record.id === id)) ?? [];
  const refresh = (): void => { void local.refetch(); void exactCloud.refetch(); if (note.meetingId) void cloud.refetch(); };
  const loading = local.isPending || exactCloud.isFetching || cloud.isFetching;
  return <div className="mb-5 min-w-0" aria-label="Recordings in this note">
    {active && <>
      {!exactIds.includes(active.record.id) && <p className="mb-2 text-xs text-muted-foreground">Another recording from this meeting · {active.record.title || "Recording"}</p>}
      {exactIds.includes(active.record.id) && !!note.recordingIds?.length && <p className="mb-2 text-xs text-muted-foreground">Attached recording</p>}
      {onAttach && !exactIds.includes(active.record.id) && <Button variant="outline" className="mb-2 h-11 rounded-full text-xs" onClick={() => onAttach(active.record)}>Attach this recording to note</Button>}
      {active.archive
        ? <CloudRecordingPlayer key={active.key} archive={active.archive} embedded onClose={refresh} onImportTranscript={onImportTranscript} />
        : <RecordingPlayer key={active.key} record={active.record} embedded onClose={refresh} onImportTranscript={onImportTranscript} />}
      {onContext && <NotebookRecordingPassages key={`passages:${active.key}`} record={active.record} onChoose={onContext} />}
      {sources.length > 1 && <label className="mt-1 flex min-h-11 items-center gap-2 text-xs text-muted-foreground">Recording<select aria-label="Choose recording source" value={active.key} onChange={(event) => setSelected(event.target.value)} className="min-h-11 min-w-0 max-w-full flex-1 truncate bg-background text-xs text-foreground">{sources.map((item) => <option key={item.key} value={item.key}>{item.record.title || "Recording"} · {recordingTime(item.record.duration)} · {item.archive ? "Cloud backup" : "This browser"}{item.ready ? "" : " · Incomplete"}</option>)}</select></label>}
    </>}
    {!!missingAttachments.length && !loading && <p role="status" className="py-3 text-xs text-muted-foreground">{missingAttachments.length} attached recording(s) unavailable here. Retry backups or open the original browser. No other recording was substituted.</p>}
    {!active && !!sources.length && !loading && <Button variant="ghost" className="h-11 text-xs" onClick={() => setSelected(sources[0].key)}>Browse other recordings from this meeting</Button>}
    {!active && loading && <p role="status" className="py-5 text-xs text-muted-foreground">Checking recordings…</p>}
    {!active && !loading && !!note.meetingId && <p className="py-3 text-xs leading-relaxed text-muted-foreground">No video available at this website address yet. Open the browser where you recorded, or save a private cloud backup there to watch on other devices.</p>}
    {(local.isError || exactCloud.isError || exactCloud.isPaused || cloud.isError) && <div className="flex items-center gap-2 text-xs text-muted-foreground"><span>Some recording sources couldn’t load.</span><Button variant="ghost" className="h-11 text-xs" onClick={refresh}>Retry recordings</Button></div>}
    {cloud.hasNextPage && <Button variant="ghost" className="h-11 text-xs" disabled={cloud.isFetchingNextPage} onClick={() => void cloud.fetchNextPage()}>Load older recordings</Button>}
  </div>;
}
