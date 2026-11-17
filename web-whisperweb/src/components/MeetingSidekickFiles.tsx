import { useState } from "react";
import { useInfiniteQuery, useMutation } from "@tanstack/react-query";
import { FileText, Check, Search, X } from "lucide-react";
import { fetchNotebookArchive } from "@/lib/notebookArchive";
import { noteFile, sidekickTranscript, speechFile, type SidekickFile } from "@/lib/meetingSidekick";
import type { NotebookDocument } from "@/lib/notebookDocument";
import type { WhisperMeeting } from "@/lib/meetings";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";
import { Button } from "./ui/button";
import { toast } from "sonner";

/** Inline picker avoids meeting/fullscreen portal conflicts. Reads only an explicitly tapped transcript. */
export function MeetingSidekickFiles({ owner, meetingID, notes, selected, onAdd, onRemove, onClose }: { owner: string; meetingID: string; notes: NotebookDocument[]; selected: SidekickFile[]; onAdd: (file: SidekickFile) => void; onRemove: (id: string) => void; onClose: () => void }): JSX.Element {
  const [query, setQuery] = useState<string>("");
  const begin = useChatOperationGuard(owner, meetingID);
  const archive = useInfiniteQuery({ queryKey: ["sidekick-meetings", owner], initialPageParam: 0, queryFn: ({ pageParam, signal }) => fetchNotebookArchive(owner, pageParam, signal, true), getNextPageParam: (last, pages) => last.hasMore ? pages.length : undefined, gcTime: 0 });
  const load = useMutation({ networkMode: "always", mutationFn: async (meeting: WhisperMeeting) => {
    const check = begin(); const result = await sidekickTranscript(owner, meeting.id, new AbortController().signal); check();
    if (!result.complete) throw new Error("This transcript exceeds 200 passages. Choose a shorter saved excerpt from Notebook instead; nothing was shortened or sent.");
    return speechFile(meeting.id, meeting.title, result.rows, "selected past transcript");
  }, onSuccess: onAdd, onError: (error: Error) => toast.error(error.message) });
  const matches = (title: string): boolean => title.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase());
  const chooseNote = (note: NotebookDocument): void => { try { onAdd(noteFile(note)); } catch (error) { toast.error((error as Error).message); } };
  const meetings = [...new Map((archive.data?.pages.flatMap((page) => page.meetings) ?? []).map((meeting) => [meeting.id, meeting])).values()].filter((meeting) => meeting.id !== meetingID && matches(meeting.title));
  return <section aria-label="Choose sidekick files" className="space-y-3 border-b border-border p-5">
    <div className="flex items-center justify-between"><h3 className="font-serif text-xl">Bring your context.</h3><Button variant="ghost" size="icon" className="h-11 w-11" aria-label="Close file picker" onClick={onClose}><X className="h-4 w-4" /></Button></div>
    <p className="text-xs leading-5 text-muted-foreground">Select past transcripts or private notes. Only chosen files join your next Jasper request. No audio files are sent.</p>
    <label className="flex min-h-11 items-center gap-2 border-b border-border"><Search className="h-4 w-4" /><input aria-label="Search sidekick files" placeholder="Search meetings, notes, folders…" className="min-w-0 flex-1 bg-transparent text-sm outline-none" value={query} onChange={(event) => setQuery(event.target.value)} /></label>
    {selected.map((file) => <Button key={file.id} variant="secondary" className="h-auto min-h-11 w-full justify-between whitespace-normal text-left text-xs" onClick={() => onRemove(file.id)}><span>{file.title}</span><Check className="ml-2 h-4 w-4 shrink-0" /></Button>)}
    <div className="max-h-64 overflow-y-auto"><p className="py-3 text-[10px] font-semibold uppercase tracking-widest text-muted-foreground">Private notes</p>{notes.filter((note) => matches(`${note.title} ${note.folder} ${note.people}`) && !selected.some((file) => file.id === `note:${note.id}`)).map((note) => <button key={note.id} className="flex min-h-14 w-full items-center gap-3 border-b border-border py-3 text-left text-sm" onClick={() => chooseNote(note)}><FileText className="h-4 w-4 shrink-0" /><span>{note.title || "Untitled note"}<small className="block text-muted-foreground">{note.folder || "Private note"} · {note.updatedAt.slice(0, 10)}</small></span></button>)}
    <p className="py-3 text-[10px] font-semibold uppercase tracking-widest text-muted-foreground">Past meeting transcripts</p>{meetings.filter((meeting) => !selected.some((file) => file.id === `meeting:${meeting.id}`)).map((meeting) => <button key={meeting.id} disabled={load.isPending} className="flex min-h-14 w-full items-center gap-3 border-b border-border py-3 text-left text-sm disabled:opacity-50" onClick={() => load.mutate(meeting)}><FileText className="h-4 w-4 shrink-0" /><span>{meeting.title}<small className="block text-muted-foreground">{(meeting.ended_at ?? meeting.created_at)?.slice(0, 10)} · Load saved transcript</small></span></button>)}</div>
    {(load.isPending || archive.isPending) && <p role="status" className="text-xs">Reading selected meeting files…</p>}{archive.isError && <Button variant="ghost" onClick={() => void archive.refetch()}>Retry meeting library</Button>}{archive.hasNextPage && <Button variant="ghost" className="h-11 text-xs" disabled={archive.isFetchingNextPage} onClick={() => void archive.fetchNextPage()}>Load older meetings</Button>}
  </section>;
}
