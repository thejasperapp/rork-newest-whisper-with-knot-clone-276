import { z } from "zod";
import { supabase } from "./supabase";
import { notebookSources, type NotebookDocument, type NotebookSource } from "./notebookDocument";

const speechSchema = z.object({ id: z.string().uuid(), meeting_id: z.string().uuid(), username: z.string(), text: z.string(), spoken_at: z.string() });
export type SidekickSpeech = z.infer<typeof speechSchema>;
/** Explicit, immutable file context; selection never grants access to other meetings. */
export type SidekickFile = { id: string; title: string; sources: NotebookSource[] };

/** Latest saved window, with a sentinel so a partial transcript cannot masquerade as complete. */
export async function sidekickTranscript(owner: string, meetingID: string, signal: AbortSignal): Promise<{ rows: SidekickSpeech[]; complete: boolean }> {
  const session = await supabase.auth.getSession(); signal.throwIfAborted();
  if (session.data.session?.user.id !== owner) throw new Error("Sign in again to read this meeting.");
  const { data, error } = await supabase.from("whisper_meeting_transcripts").select("id,meeting_id,username,text,spoken_at").eq("meeting_id", meetingID).order("spoken_at", { ascending: false }).order("id", { ascending: false }).limit(201).abortSignal(signal);
  signal.throwIfAborted();
  if (error) throw new Error("Saved speech is delayed or unavailable. Retry without leaving the call.");
  const current = await supabase.auth.getSession(); signal.throwIfAborted();
  if (current.data.session?.user.id !== owner) throw new Error('Your account changed. Reopen the meeting.');
  const rows = z.array(speechSchema).parse(data);
  if (rows.some((row) => row.meeting_id !== meetingID)) throw new Error("Couldn't verify this transcript.");
  return { rows: rows.slice(0, 200).reverse(), complete: rows.length <= 200 };
}

export function speechFile(meetingID: string, title: string, rows: SidekickSpeech[], label: string): SidekickFile {
  const provenance = `${title.slice(0, 160)} · meeting ${meetingID} · ${label} · through ${rows[rows.length - 1]?.spoken_at ?? "no speech"}`;
  return { id: `meeting:${meetingID}`, title, sources: notebookSources({ notes: "", transcript: rows.map((row) => `[${row.spoken_at}] ${row.username || "Speaker"}: ${row.text}`).join("\n") }).map((source) => ({ ...source, provenance })) };
}

export function noteFile(note: NotebookDocument): SidekickFile {
  return { id: `note:${note.id}`, title: note.title || "Untitled note", sources: notebookSources(note).map((source) => ({ ...source, provenance: `${note.title.slice(0, 160)} · note ${note.id} · revision ${note.storageRevision} · ${note.updatedAt}` })) };
}

/** Prefixes each selected item independently and rejects excess, never silently truncates evidence. */
export function sidekickSources(files: SidekickFile[]): NotebookSource[] {
  if (!files.length || files.length > 8 || new Set(files.map((file) => file.id)).size !== files.length) throw new Error("Choose between one and eight unique context items, including this meeting.");
  const sources = files.flatMap((file, index) => file.sources.map((source) => ({ ...source, id: `M${index + 1}-${source.id}` })));
  if (!sources.length || sources.length > 160 || sources.reduce((sum, item) => sum + item.text.length, 0) > 24000 || sources.some((source) => source.text.length > 1200 || source.id.length > 20) || new Set(sources.map((item) => item.id)).size !== sources.length) throw new Error("This context is too large. Choose a shorter speech range or fewer files (24,000 characters / 160 passages).");
  return sources;
}

export const SIDEKICK_RECIPES = [
  { title: "What did I miss?", question: "Catch me up on the selected speech. What matters now? Distinguish decisions from proposals.", workflow: "ask" },
  { title: "Decisions", question: "Which decisions were actually made and which questions remain open?", workflow: "ask" },
  { title: "Suggest questions", question: "Suggest useful next questions grounded in unresolved points in these sources. Label suggestions as questions, not meeting facts.", workflow: "ask" },
  { title: "What's changed?", question: "Compare the current meeting with the selected past files. What changed or conflicts? Use source dates and do not invent consensus.", workflow: "compare" },
  { title: "Recap next steps", question: "Draft the supported follow-ups for review. Do not send anything or invent an owner or due date.", workflow: "followups" },
  { title: "Generate notes", question: "Turn the selected speech and my writing into organized meeting notes. Keep uncertainties and open questions visible.", workflow: "enhance" },
  { title: "Make me sound smart", question: "Suggest two concise contributions I could make based on the selected sources. Distinguish supported facts from suggestions; do not invent evidence.", workflow: "ask" },
] as const;
