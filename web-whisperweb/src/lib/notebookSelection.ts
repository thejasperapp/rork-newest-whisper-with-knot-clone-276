import { notebookSources, type NotebookDocument, type NotebookSource } from "./notebookDocument";

/** Explicitly selected, owner-checked notes only. No shared recap or automatic archive ingestion. */
export function notebookSelectionSources(ownerId: string, documents: NotebookDocument[]): NotebookSource[] {
  if (!documents.length || documents.length > 8 || new Set(documents.map((entry) => entry.id)).size !== documents.length) throw new Error("Choose between one and eight notes.");
  const sources = documents.flatMap((entry, index) => {
    if (entry.ownerId !== ownerId || entry.deletedAt) throw new Error("These notes are no longer available in this account.");
    return notebookSources(entry).map((source) => ({ ...source, id: `M${index + 1}-${source.id}` }));
  });
  if (sources.length > 160 || sources.reduce((total, source) => total + source.text.length, 0) > 24000) throw new Error("Select fewer or shorter notes. Jasper reads up to 24,000 characters at a time; nothing was truncated.");
  return sources;
}
