import { useState } from "react";
import { toast } from "sonner";
import { notebookSources, type NotebookSource } from "@/lib/notebookDocument";
import { recordingTranscriptText } from "@/lib/recordingNotebookText";
import { recordingTime, type MeetingRecording } from "@/lib/meetingRecordingModel";
import { Button } from "./ui/button";

/** Select transcript evidence separately from playback, attachment and cloud byte storage. */
export function NotebookRecordingPassages({ record, onChoose }: { record: MeetingRecording; onChoose: (context: { sources: NotebookSource[]; label: string }) => void }): JSX.Element {
  const [selected, setSelected] = useState<string[]>([]);
  const [count, setCount] = useState<number>(50);
  return <details className="border-b border-border"><summary className="min-h-11 cursor-pointer py-3 text-xs">Choose recording passages for Jasper</summary><p className="mb-2 text-xs text-muted-foreground">Only selected transcript passages will be used. No audio or video is sent.</p><div className="max-h-48 overflow-y-auto">{record.transcript.slice(0, count).map((passage) => <label key={passage.id} className="flex min-h-11 gap-2 py-3 text-xs leading-5"><input type="checkbox" className="mt-1" checked={selected.includes(passage.id)} onChange={(event) => setSelected((prior) => event.target.checked ? [...prior, passage.id] : prior.filter((id) => id !== passage.id))} /><span>{recordingTime(passage.start)}–{recordingTime(passage.end)}{passage.timing === "chunk" ? " · approximate" : ""}<span className="block">{passage.text}</span></span></label>)}</div>{count < record.transcript.length && <Button variant="ghost" className="h-11 text-xs" onClick={() => setCount((value) => value + 50)}>More transcript passages</Button>}<Button variant="outline" className="my-2 h-11 rounded-full text-xs" disabled={!selected.length} onClick={() => { try { const passages = record.transcript.filter((row) => selected.includes(row.id)); const sources = notebookSources({ notes: "", transcript: recordingTranscriptText(passages) }); const label = `Recording ${record.title || "Meeting"} · ${record.id} · revision ${record.revision} · ${passages.length} selected passages`; onChoose({ sources: sources.map((source) => ({ ...source, provenance: label })), label }); } catch (error) { toast.error((error as Error).message); } }}>Use these passages as context</Button>{!record.transcript.length && <p className="pb-3 text-xs text-muted-foreground">No saved transcript for this recording. Playback remains available.</p>}</details>;
}
