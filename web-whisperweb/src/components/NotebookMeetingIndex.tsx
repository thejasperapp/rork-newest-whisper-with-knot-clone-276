import { useMemo } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link } from "react-router-dom";
import { ChevronRight, NotebookPen } from "lucide-react";
import { listNotebookDocuments } from "@/lib/notebookStorage";
import { listRecordings } from "@/lib/meetingRecordingStorage";

/** Group existing local content by room identity; never creates shared meeting data. */
export function NotebookMeetingIndex({ ownerId }: { ownerId: string }): JSX.Element | null {
  const notes = useQuery({ queryKey: ["personal-notebook", ownerId], queryFn: () => listNotebookDocuments(ownerId) });
  const recordings = useQuery({ queryKey: ["recordings", ownerId], queryFn: () => listRecordings(ownerId), networkMode: "always" });
  const meetings = useMemo(() => {
    const groups = new Map<string, { id: string; title: string; notes: number; recordings: number }>();
    for (const note of notes.data ?? []) { if (!note.meetingId) continue; const group = groups.get(note.meetingId) ?? { id: note.meetingId, title: note.title || "Meeting", notes: 0, recordings: 0 }; group.notes++; groups.set(note.meetingId, group); }
    for (const record of recordings.data ?? []) { if (!record.meetingId) continue; const group = groups.get(record.meetingId) ?? { id: record.meetingId, title: record.title || "Meeting", notes: 0, recordings: 0 }; if (record.title && group.recordings === 0) group.title = record.title; group.recordings++; groups.set(record.meetingId, group); }
    return [...groups.values()];
  }, [notes.data, recordings.data]);
  if (!meetings.length) return null;
  return <section aria-label="Meeting notebooks" className="mb-8 border-b border-border pb-6"><h2 className="text-lg font-semibold">By meeting</h2><p className="mt-1 text-xs text-muted-foreground">Open a meeting to see its private notes and recordings together. These groups and counts come from this browser. Cloud backups load inside; cloud-only meetings remain in the full recordings list below.</p><div className="mt-3 divide-y divide-border">{meetings.map((meeting) => <Link key={meeting.id} to={`/notebook?portal=workspace&meeting=${encodeURIComponent(meeting.id)}&title=${encodeURIComponent(meeting.title)}`} className="flex min-h-20 items-center gap-3 py-3"><NotebookPen className="h-5 w-5 shrink-0 text-[#F22659]" /><span className="min-w-0 flex-1"><span className="block truncate text-sm font-semibold">{meeting.title}</span><span className="text-xs text-muted-foreground">{meeting.notes} notes · {meeting.recordings} recordings on this browser</span></span><ChevronRight className="h-4 w-4" /></Link>)}</div></section>;
}
