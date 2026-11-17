import { z } from "zod";
import type { NotebookDocument } from "./notebookDocument";

/** UTF-16 anchors match browser selection and iPhone NSRange; quoted evidence survives edits. */
export const notebookHighlightSchema = z.object({
  id: z.string().uuid(), kind: z.enum(["notes", "transcript"]), start: z.number().int().min(0).max(60000), end: z.number().int().min(1).max(60000),
  text: z.string().min(1).max(1200), revision: z.number().int().nonnegative(), origin: z.enum(["manual", "jasper"]), stale: z.boolean(),
}).refine((value) => value.end > value.start && value.end - value.start === value.text.length);
export type NotebookHighlight = z.infer<typeof notebookHighlightSchema>;
export type NotebookSelection = { kind: "notes" | "transcript"; start: number; end: number; text: string; revision: number };

/** Only edits strictly outside a retained quote can move its anchor. Ambiguity becomes stale. */
export function rebaseHighlights(highlights: NotebookHighlight[], kind: NotebookHighlight["kind"], before: string, after: string, revision: number): NotebookHighlight[] {
  if (before === after) return highlights;
  let prefix = 0, suffix = 0;
  while (prefix < Math.min(before.length, after.length) && before[prefix] === after[prefix]) ++prefix;
  while (suffix < Math.min(before.length, after.length) - prefix && before[before.length - 1 - suffix] === after[after.length - 1 - suffix]) ++suffix;
  return highlights.map((item) => {
    if (item.kind !== kind || item.stale) return item;
    if (item.end <= prefix) return { ...item, revision };
    if (item.start >= before.length - suffix) return { ...item, start: item.start + after.length - before.length, end: item.end + after.length - before.length, revision };
    return { ...item, stale: true };
  });
}

export function selectedHighlight(document: NotebookDocument, selection: NotebookSelection, origin: NotebookHighlight["origin"]): NotebookHighlight {
  if (selection.revision !== document.revision || document[selection.kind].slice(selection.start, selection.end) !== selection.text || !selection.text.trim()) throw new Error("Select that passage again; the writing has changed.");
  if (selection.text.length > 1200) throw new Error("Highlight up to 1,200 characters at once.");
  return notebookHighlightSchema.parse({ ...selection, id: crypto.randomUUID(), origin, stale: false });
}
