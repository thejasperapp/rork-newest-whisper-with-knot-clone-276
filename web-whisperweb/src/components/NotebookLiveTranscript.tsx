import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { z } from "zod";
import { supabase } from "@/lib/supabase";
import { notebookSources, type NotebookSource } from "@/lib/notebookDocument";
import { Button } from "./ui/button";
import { toast } from "sonner";

const segment = z.object({ id: z.string().uuid(), meeting_id: z.string().uuid(), username: z.string(), text: z.string(), spoken_at: z.string() });
/** Read-only confirmed speech. Choosing context never mutates a meeting or starts capture. */
export function NotebookLiveTranscript({ owner, meetingId, onChoose }: { owner: string; meetingId: string; onChoose: (context: { sources: NotebookSource[]; label: string }) => void }): JSX.Element {
  const [selected, setSelected] = useState<string[]>([]);
  const transcript = useQuery({ queryKey: ["notebook-live-transcript", owner, meetingId], gcTime: 0, refetchInterval: 5000, queryFn: async ({ signal }) => {
    const session = await supabase.auth.getSession(); signal.throwIfAborted();
    if (session.data.session?.user.id !== owner) throw new Error("Sign in again to read this meeting's transcript.");
    const { data, error, count } = await supabase.from("whisper_meeting_transcripts").select("id,meeting_id,username,text,spoken_at", { count: "exact" }).eq("meeting_id", meetingId).order("spoken_at", { ascending: false }).order("id", { ascending: false }).limit(200).abortSignal(signal);
    if (error) throw new Error("Saved speech is unavailable. Transcription may be delayed; reconnect and retry.");
    const rows = z.array(segment).parse(data).filter((row) => row.meeting_id === meetingId).reverse();
    return { rows, complete: count !== null && count === rows.length };
  } });
  const rows = transcript.data?.rows ?? [];
  const choose = (all: boolean): void => {
    const chosen = rows.filter((row) => all || selected.includes(row.id));
    try {
      const text = chosen.map((row) => `[${row.spoken_at}] ${row.username || "Speaker"}: ${row.text}`).join("\n");
      const sources = notebookSources({ notes: "", transcript: text });
      const label = `${all ? "Transcript so far" : "Chosen saved speech"} · meeting ${meetingId} · through ${chosen[chosen.length - 1]?.spoken_at}`;
      onChoose({ sources: sources.map((source) => ({ ...source, provenance: label })), label });
    } catch (error) { toast.error((error as Error).message); }
  };
  return <details className="mb-4 border-y border-border"><summary className="min-h-11 cursor-pointer py-3 text-sm">Live transcript · choose context</summary><p className="mb-3 text-xs text-muted-foreground">Confirmed saved speech only. Provisional captions are excluded. Available speech may not cover everyone. Selecting context sends nothing until you tap a Jasper action.</p>{transcript.isPending && <p role="status" className="py-3 text-xs">Checking saved speech…</p>}{transcript.isError && <p role="alert" className="text-xs">{transcript.error.message}</p>}<div className="max-h-52 overflow-y-auto">{rows.map((row) => <label key={row.id} className="flex min-h-11 items-start gap-2 py-3"><input type="checkbox" className="mt-1" checked={selected.includes(row.id)} onChange={(event) => setSelected((prior) => event.target.checked ? [...prior, row.id] : prior.filter((id) => id !== row.id))} /><span className="text-xs leading-5"><span className="block font-semibold">{row.username || "Speaker"} · {new Date(row.spoken_at).toLocaleTimeString()}</span>{row.text}</span></label>)}</div>{!rows.length && !transcript.isPending && <p className="py-3 text-xs text-muted-foreground">No confirmed speech yet. The meeting’s existing transcription must be enabled and permitted.</p>}{transcript.data && !transcript.data.complete && <p className="text-xs">Showing the latest 200 saved passages. Choose a smaller range; earlier speech is not included.</p>}<div className="flex flex-wrap gap-2 py-3"><Button variant="outline" className="h-11 rounded-full text-xs" disabled={!selected.some((id) => rows.some((row) => row.id === id))} onClick={() => choose(false)}>Use selected speech</Button><Button variant="ghost" className="h-11 text-xs" disabled={!rows.length || !transcript.data?.complete} onClick={() => choose(true)}>Use transcript so far</Button><Button variant="ghost" className="h-11 text-xs" onClick={() => void transcript.refetch()}>Refresh</Button></div></details>;
}
