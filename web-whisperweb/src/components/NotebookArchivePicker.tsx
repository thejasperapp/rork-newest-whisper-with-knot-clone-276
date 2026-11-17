import { useMemo, useState } from "react";
import { useInfiniteQuery, useMutation, useQuery } from "@tanstack/react-query";
import { ArrowLeft, AudioLines, FileText, Search } from "lucide-react";
import { Button } from "./ui/button";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "./ui/dialog";
import { NotebookRecordingSources } from "./NotebookRecordingSources";
import { fetchMeeting, type WhisperMeeting } from "@/lib/meetings";
import { fetchNotebookArchive, importArchivedMeetingNote } from "@/lib/notebookArchive";
import type { NotebookDocument } from "@/lib/notebookDocument";
import type { MeetingRecording } from "@/lib/meetingRecordingModel";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";

/** Browse generated meeting notes without granting AI access or changing the current selection. */
export function NotebookArchivePicker({ ownerId, meetingId, adding, disabled, onChoose, onClose, initialMeeting }: { initialMeeting?: WhisperMeeting | null; ownerId: string; meetingId: string | null; adding: boolean; disabled: boolean; onChoose: (note: NotebookDocument) => void; onClose: () => void }): JSX.Element {
  const [search, setSearch] = useState<string>("");
  const [preview, setPreview] = useState<WhisperMeeting | null>(initialMeeting ?? null);
  const [recording, setRecording] = useState<MeetingRecording | null>(null);
  const [attach, setAttach] = useState<boolean>(true);
  const begin = useChatOperationGuard(ownerId, `archive:${preview?.id ?? "list"}`);
  const archive = useInfiniteQuery({ queryKey: ["notebook-archive", ownerId], initialPageParam: 0, queryFn: ({ pageParam, signal }) => fetchNotebookArchive(ownerId, pageParam, signal), getNextPageParam: (last, pages) => last.hasMore ? pages.length : undefined, gcTime: 0 });
  const linked = useQuery({ queryKey: ["notebook-meeting", ownerId, meetingId], enabled: !!meetingId, queryFn: () => fetchMeeting(meetingId!), gcTime: 0 });
  const meetings = useMemo(() => {
    const unique = new Map<string, WhisperMeeting>();
    for (const meeting of [linked.data, ...(archive.data?.pages.flatMap((page) => page.meetings) ?? [])]) if (meeting?.summary?.trim()) unique.set(meeting.id, meeting);
    return [...unique.values()].filter((meeting) => [meeting.title, meeting.summary ?? ""].some((value) => value.toLocaleLowerCase().includes(search.toLocaleLowerCase()))).sort((a, b) => Number(b.id === meetingId) - Number(a.id === meetingId) || (b.ended_at ?? b.created_at ?? "").localeCompare(a.ended_at ?? a.created_at ?? ""));
  }, [linked.data, archive.data, search, meetingId]);
  const useNote = useMutation({ mutationFn: async () => {
    const check = begin();
    if (!preview || disabled) throw new Error("Finish saving the open note first.");
    const ids = attach && recording?.ownerId === ownerId && recording.meetingId === preview.id ? [recording.id] : [];
    const saved = await importArchivedMeetingNote(ownerId, preview, ids, check); check(); return saved;
  }, onSuccess: onChoose });
  return <Dialog open onOpenChange={(open) => { if (!open && !useNote.isPending) onClose(); }}><DialogContent className="max-h-[90dvh] max-w-2xl overflow-y-auto">
    <DialogHeader><DialogTitle className="font-serif text-2xl">Notes archive</DialogTitle><DialogDescription>Meeting-generated notes, ready to revisit with Jasper. Shared originals stay unchanged.</DialogDescription></DialogHeader>
    {preview ? <div className="min-w-0">
      <Button variant="ghost" className="mb-3 h-11" disabled={useNote.isPending} onClick={() => { setPreview(null); setRecording(null); useNote.reset(); }}><ArrowLeft className="mr-2 h-4 w-4" />All archived notes</Button>
      <h2 className="font-serif text-3xl">{preview.title || "Meeting"}</h2><p className="my-3 text-xs text-muted-foreground">{(preview.ended_at ?? preview.created_at)?.slice(0, 10)} · AI-generated meeting note</p>
      <NotebookRecordingSources key={preview.id} note={{ id: preview.id, ownerId, meetingId: preview.id }} onRecordingChange={setRecording} />
      <p className="max-h-64 overflow-y-auto whitespace-pre-wrap border-y border-border py-4 text-sm leading-relaxed">{preview.summary}</p>
      {recording && <label className="flex min-h-11 items-center gap-3 py-3 text-sm"><input type="checkbox" checked={attach} onChange={(event) => setAttach(event.target.checked)} /><AudioLines className="h-4 w-4 shrink-0" />Attach this recording · {recording.title}</label>}
      <p className="my-3 text-xs leading-relaxed text-muted-foreground">Use in Notebook saves a private, editable copy and {adding ? "adds it to your selection" : "opens it for writing"}. If you already have a copy, your edits and attachments are kept. No transcript, upload or AI request is automatic.</p>
      <Button className="h-11 rounded-full" disabled={disabled || useNote.isPending} onClick={() => useNote.mutate()}>{useNote.isPending ? "Opening private copy…" : adding ? "Use in Notebook · add to selection" : "Use in Notebook"}</Button>
      {useNote.error && <p role="alert" className="mt-3 text-sm">{useNote.error.message}</p>}
    </div> : <>
      <label className="flex min-h-11 items-center gap-2 border-b border-border"><Search className="h-4 w-4 text-muted-foreground" /><input aria-label="Search notes archive" className="min-w-0 flex-1 bg-transparent text-sm outline-none" placeholder="Search meeting notes" value={search} onChange={(event) => setSearch(event.target.value)} /></label>
      {archive.isPending && <p role="status" className="py-3 text-sm">Opening your notes archive…</p>}
      <div className="divide-y divide-border">{meetings.map((meeting) => <button key={meeting.id} className="flex min-h-20 w-full items-start gap-3 py-4 text-left" onClick={() => { setPreview(meeting); setRecording(null); setAttach(true); }}><FileText className="mt-1 h-5 w-5 shrink-0 text-[#F22659]" /><span className="min-w-0"><span className="block font-medium">{meeting.title || "Meeting"}</span><span className="mt-1 block text-xs text-muted-foreground">{(meeting.ended_at ?? meeting.created_at)?.slice(0, 10)} · Generated from meeting{meeting.id === meetingId ? " · This meeting" : ""}</span><span className="mt-2 line-clamp-2 text-xs text-muted-foreground">{meeting.summary}</span></span></button>)}</div>
      {!archive.isPending && !archive.isError && !meetings.length && <p className="py-5 text-sm text-muted-foreground">{search ? "No matching notes on loaded pages. Load older notes to search further." : "No generated meeting notes on these pages yet."}</p>}
      {(archive.isError || linked.isError) && <div role="alert" className="text-sm">Couldn't load some archived notes.<Button variant="ghost" className="h-11" onClick={() => { void archive.refetch(); if (meetingId) void linked.refetch(); }}>Retry archive</Button></div>}
      {archive.hasNextPage && <Button variant="ghost" className="h-11" disabled={archive.isFetchingNextPage} onClick={() => void archive.fetchNextPage()}>Load older meeting notes</Button>}
    </>}
  </DialogContent></Dialog>;
}
