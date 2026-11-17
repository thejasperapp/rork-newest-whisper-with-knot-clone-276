import { describe, expect, it } from "vitest";
import { newNotebookDocument, notebookDocumentSchema } from "./notebookDocument";
import { rebaseHighlights, selectedHighlight } from "./notebookHighlights";

const owner = "00000000-0000-4000-8000-000000000001";
const note = () => ({ ...newNotebookDocument(owner), notes: "before important after", revision: 3 });
const selected = () => selectedHighlight(note(), { kind: "notes", start: 7, end: 16, text: "important", revision: 3 }, "manual");
describe("persistent passage anchors", () => {
  it("round-trips exact evidence in an account-saving document", () => {
    const document = notebookDocumentSchema.parse(JSON.parse(JSON.stringify({ ...note(), highlights: [selected()] })));
    expect(document.highlights?.[0].text).toBe("important"); expect(document.syncEnabled).toBe(true);
  });
  it("moves only anchors outside an insertion", () => {
    const [moved] = rebaseHighlights([selected()], "notes", note().notes, "new before important after", 4);
    expect(moved).toMatchObject({ start: 11, end: 20, stale: false, revision: 4 });
  });
  it("retains the original quote as stale when evidence is changed", () => {
    const [stale] = rebaseHighlights([selected()], "notes", note().notes, "before incorrect after", 4);
    expect(stale).toMatchObject({ text: "important", stale: true });
  });
  it("does not attach deleted evidence to a repeated quote elsewhere", () => {
    const [stale] = rebaseHighlights([selected()], "notes", note().notes, "before after important", 4);
    expect(stale.stale).toBe(true);
  });
  it("does not rewrite anchors in the other text field", () => {
    const highlight = selected();
    expect(rebaseHighlights([highlight], "transcript", "source", "changed", 4)).toEqual([highlight]);
  });
  it("rejects stale selection, forged quotes and excessive anchors", () => {
    expect(() => selectedHighlight(note(), { kind: "notes", start: 7, end: 16, text: "important", revision: 2 }, "manual")).toThrow("again");
    expect(() => selectedHighlight(note(), { kind: "notes", start: 7, end: 16, text: "fabricate", revision: 3 }, "jasper")).toThrow("again");
    expect(notebookDocumentSchema.safeParse({ ...note(), highlights: Array.from({ length: 101 }, selected) }).success).toBe(false);
  });
  it("counts emoji in UTF-16 like native NSRange", () => {
    const document = { ...note(), notes: "a😀b" };
    expect(selectedHighlight(document, { kind: "notes", start: 1, end: 3, text: "😀", revision: 3 }, "manual")).toMatchObject({ start: 1, end: 3 });
  });
});
