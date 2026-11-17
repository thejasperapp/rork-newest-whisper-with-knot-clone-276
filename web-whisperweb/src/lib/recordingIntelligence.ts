import { newNotebookDocument, notebookSources } from "./notebookDocument";
import { runNotebookIntelligence } from "./notebookIntelligence";
import type { MeetingRecording, RecordingMarker, TimedPassage } from "./meetingRecordingModel";

/** Deterministic source mapping: model citations resolve to capture positions, never model-invented timestamps. */
export function recordingEvidence(passages: TimedPassage[]): { transcript: string; positions: Map<string, TimedPassage> } {
  const lines: string[] = []; const positions = new Map<string, TimedPassage>(); let index = 0;
  for (const passage of passages) {
    const text = passage.text.replace(/\s+/g, " ").trim();
    for (let start = 0; start < text.length; start += 1200) { lines.push(text.slice(start, start + 1200)); positions.set(`T${++index}`, passage); }
  }
  const transcript = lines.join("\n"); notebookSources({ notes: "", transcript });
  return { transcript, positions };
}

/** Read a user-selected window; every proposed decision awaits review and keeps original transcript IDs. */
export async function proposeRecordingDecisions(recording: MeetingRecording, start: number, end: number, assertCurrent: () => void, signal: AbortSignal): Promise<RecordingMarker[]> {
  if (!recording.cloudConsent) throw new Error("Cloud analysis was not included in this recording’s permission.");
  const evidence = recordingEvidence(recording.transcript.filter((p) => p.start >= start && p.start < end));
  const document = { ...newNotebookDocument(recording.ownerId, recording.meetingId, recording.title), transcript: evidence.transcript };
  const result = await runNotebookIntelligence(document, "List only decisions explicitly agreed in these transcript passages. Exclude proposals, open questions and speculation. Each bullet should state one decision. If no decision is supported return insufficient true. Do not invent timestamps.", assertCurrent, signal);
  assertCurrent();
  return result.sections.flatMap((section) => section.items).map((item) => {
    const sources = item.sourceIds.map((id) => evidence.positions.get(id));
    if (sources.some((source) => !source)) throw new Error("Jasper returned an unknown recording source. Nothing was saved.");
    return { id: crypto.randomUUID(), seconds: Math.min(...sources.map((source) => source!.start)), title: item.text.slice(0, 300), kind: "decision", sourceIds: [...new Set(sources.map((source) => source!.id))], reviewed: false };
  });
}
