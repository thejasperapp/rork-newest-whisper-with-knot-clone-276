import { z } from "zod";
import { notebookHighlightSchema } from "./notebookHighlights";

const sourceSchema = z.object({ id: z.string().max(20), kind: z.enum(["notes", "transcript"]), text: z.string().max(1200), provenance: z.string().max(600).optional() });
const itemSchema = z.object({ text: z.string().trim().min(1).max(1200), sourceIds: z.array(z.string().max(20)).min(1).max(8) });
const proposalSchema = z.object({ title: z.string().trim().min(1).max(300), owner: z.string().max(80), when: z.string().max(80), sourceIds: z.array(z.string().max(20)).min(1).max(8) });
const resultSchema = z.object({
  insufficient: z.boolean(),
  sections: z.array(z.object({ title: z.string().max(80), items: z.array(itemSchema).max(8) })).max(6),
  actions: z.array(proposalSchema).max(8),
});
const enhancementSchema = resultSchema.extend({ revision: z.number().int().nonnegative(), generatedAt: z.string(), sources: z.array(sourceSchema).max(160) });

/** Private account document with a local recovery journal; never a shared meeting row. */
export const notebookDocumentSchema = z.object({
  version: z.literal(1), id: z.string().uuid(), ownerId: z.string().uuid(),
  syncEnabled: z.boolean().optional(), cloudRevision: z.number().int().nonnegative().optional(),
  syncedStorageRevision: z.number().int().nonnegative().optional(), syncOperationId: z.string().uuid().optional(),
  deletedAt: z.string().optional(), isMeetingWriting: z.boolean().optional(),
  highlights: z.array(notebookHighlightSchema).max(100).optional(),
  recapCopiedAt: z.string().optional(), recordingIds: z.array(z.string().uuid()).max(30).optional(),
  title: z.string().max(160), folder: z.string().max(80), people: z.string().max(300),
  meetingId: z.string().max(200).nullable().default(null), templateId: z.string().max(60), instructions: z.string().max(1000),
  notes: z.string().max(60000), transcript: z.string().max(60000),
  revision: z.number().int().nonnegative(), storageRevision: z.number().int().nonnegative(),
  createdAt: z.string(), updatedAt: z.string(), enhancement: enhancementSchema.nullable().default(null),
  commitments: z.array(z.object({ id: z.string().uuid(), title: z.string().min(1).max(300), owner: z.string().max(80), when: z.string().max(80), done: z.boolean(), sources: z.array(sourceSchema).max(8) })).max(100),
});
export type NotebookDocument = z.infer<typeof notebookDocumentSchema>;
export type NotebookSource = z.infer<typeof sourceSchema>;
export type NotebookResult = z.infer<typeof enhancementSchema>;
export type NotebookProposal = z.infer<typeof proposalSchema>;
export type NotebookCommitment = NotebookDocument["commitments"][number];

/** Templates change Jasper's outline, never replace the user's writing. */
export const NOTEBOOK_TEMPLATES = [
  { id: "general", label: "Meeting", hint: "Summary, decisions, open questions" },
  { id: "one-on-one", label: "1:1", hint: "Progress, feedback, support needed" },
  { id: "project", label: "Project", hint: "Updates, blockers, decisions" },
  { id: "client", label: "Client", hint: "Goals, constraints, agreements" },
  { id: "interview", label: "Interview", hint: "Experience, evidence, open questions" },
] as const;

/** Creates an empty, account-scoped notebook entry; no sample meeting facts. */
export function newNotebookDocument(ownerId: string, meetingId: string | null = null, title = ""): NotebookDocument {
  const now = new Date().toISOString();
  return { version: 1, id: crypto.randomUUID(), ownerId, syncEnabled: true, title: title.slice(0, 160), folder: "", people: "", meetingId, templateId: "general", instructions: "", notes: "", transcript: "", revision: 0, storageRevision: 0, createdAt: now, updatedAt: now, enhancement: null, commitments: [] };
}

/** Builds a bounded source snapshot; never silently omits part of a long meeting. */
export function notebookSources(document: Pick<NotebookDocument, "notes" | "transcript">): NotebookSource[] {
  if (document.notes.length + document.transcript.length > 24000) throw new Error("Jasper can read up to 24,000 characters per entry. Split this into smaller notes; your full text is still saved.");
  const sources: NotebookSource[] = [];
  for (const kind of ["notes", "transcript"] as const) {
    let count = 0;
    for (const line of document[kind].split(/\r?\n/).map((part) => part.trim()).filter(Boolean)) {
      for (let start = 0; start < line.length; start += 1200) {
        sources.push({ id: `${kind === "notes" ? "N" : "T"}${++count}`, kind, text: line.slice(start, start + 1200) });
      }
    }
  }
  if (!sources.length) throw new Error("Write some notes or paste a transcript first.");
  if (sources.length > 160) throw new Error("This entry has more than 160 source passages. Split it into smaller notes before using Jasper.");
  return sources;
}

/** Rejects malformed results and invented source IDs before showing or saving them. */
export function parseNotebookResult(raw: string, sources: NotebookSource[], revision: number): NotebookResult {
  try {
    if (raw.length > 60000) throw new Error();
    const result = resultSchema.parse(JSON.parse(raw.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "")));
    if (new Set(result.sections.map((section) => section.title)).size !== result.sections.length || new Set(result.actions.map((action) => action.title)).size !== result.actions.length) throw new Error();
    if (result.sections.some((section) => new Set(section.items.map((item) => item.text)).size !== section.items.length)) throw new Error();
    const ids = new Set(sources.map((source) => source.id));
    const references = [...result.sections.flatMap((section) => section.items), ...result.actions];
    if (references.some((item) => item.sourceIds.some((id) => !ids.has(id)))) throw new Error();
    if (!result.insufficient && references.length === 0) throw new Error();
    if (result.insufficient && references.length > 0) throw new Error();
    return { ...result, revision, generatedAt: new Date().toISOString(), sources };
  } catch {
    throw new Error("Jasper couldn't produce a source-linked result. Your writing is unchanged. Please try again.");
  }
}

/** Plain-text export keeps sources and human writing separate from AI suggestions. */
export function exportNotebook(document: NotebookDocument): string {
  const lines = [`# ${document.title || "Untitled note"}`, `People: ${document.people || "Not set"}`, `Folder: ${document.folder || "Unfiled"}`, "", "## My notes", document.notes];
  if (document.transcript) lines.push("", "## Pasted transcript", document.transcript);
  if (document.enhancement) {
    lines.push("", `## Jasper draft${document.enhancement.revision !== document.revision ? " (sources have since changed)" : ""}`);
    for (const section of document.enhancement.sections) lines.push(`### ${section.title}`, ...section.items.map((item) => `- ${item.text} [${item.sourceIds.join(", ")}]`));
    lines.push("", "### Source snapshot", ...document.enhancement.sources.map((source) => `[${source.id}] ${source.provenance ?? source.kind}: ${source.text}`));
  }
  if (document.highlights?.length) lines.push("", "## Retained highlights", ...document.highlights.map((item) => `- ${item.text}\n  ${item.kind} · ${item.origin}${item.stale ? " · original quote; writing changed" : ""}`));
  lines.push("", "## Tracked follow-ups");
  for (const item of document.commitments) {
    lines.push(`- [${item.done ? "x" : " "}] ${item.title} — ${item.owner || "Unassigned"} · ${item.when || "No due date"}`);
    lines.push(...item.sources.map((source) => `  Original evidence [${source.id}] ${source.provenance ?? source.kind}: ${source.text}`));
  }
  return lines.join("\n");
}
