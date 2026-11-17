import { describe, expect, it } from "vitest";
import { exportNotebook, newNotebookDocument, notebookDocumentSchema, notebookSources, parseNotebookResult } from "./notebookDocument";

const owner = "11d2d71c-f84a-4ab1-95bd-dd1a87a2c001";
const document = (): ReturnType<typeof newNotebookDocument> => ({ ...newNotebookDocument(owner), notes: "Keep the launch focused.\nAlex will send a draft.", transcript: "Alex: I will send it Friday." });
const response = { insufficient: false, sections: [{ title: "Summary", items: [{ text: "Keep the launch focused.", sourceIds: ["N1"] }] }], actions: [{ title: "Send a draft", owner: "Alex", when: "Friday", sourceIds: ["N2", "T1"] }] };

describe("notebook source snapshots", () => {
  it("separates human writing from pasted transcript and keeps the original untouched", () => {
    const note = document(); const original = structuredClone(note);
    expect(notebookSources(note)).toEqual([{ id: "N1", kind: "notes", text: "Keep the launch focused." }, { id: "N2", kind: "notes", text: "Alex will send a draft." }, { id: "T1", kind: "transcript", text: "Alex: I will send it Friday." }]);
    expect(note).toEqual(original);
  });
  it("rejects empty input and long documents rather than silently truncating", () => {
    expect(() => notebookSources({ notes: "  \n", transcript: "" })).toThrow("Write some notes");
    expect(() => notebookSources({ notes: "x".repeat(24001), transcript: "" })).toThrow("24,000");
    expect(() => notebookSources({ notes: Array.from({ length: 161 }, () => "line").join("\n"), transcript: "" })).toThrow("160");
  });
  it("chunks long lines without losing characters", () => {
    const sources = notebookSources({ notes: "x".repeat(2500), transcript: "" });
    expect(sources.map((source) => source.text.length)).toEqual([1200, 1200, 100]);
    expect(sources.map((source) => source.text).join("")).toBe("x".repeat(2500));
  });
  it("retains citation evidence and source revision independently of later edits", () => {
    const note = document(); const result = parseNotebookResult(JSON.stringify(response), notebookSources(note), 7);
    note.notes = "Changed after generation";
    expect(result.revision).toBe(7);
    expect(result.sources[0].text).toBe("Keep the launch focused.");
    expect(result.actions[0].sourceIds).toEqual(["N2", "T1"]);
  });
  it.each(["T999", "another-meeting:N1"])("rejects invented or cross-meeting source ID %s", (sourceId) => {
    const payload = structuredClone(response); payload.sections[0].items[0].sourceIds = [sourceId];
    expect(() => parseNotebookResult(JSON.stringify(payload), notebookSources(document()), 0)).toThrow("source-linked");
  });
  it("rejects missing citations, invalid JSON and duplicate UI identities", () => {
    const payload = structuredClone(response); payload.sections[0].items[0].sourceIds = [];
    expect(() => parseNotebookResult(JSON.stringify(payload), notebookSources(document()), 0)).toThrow();
    expect(() => parseNotebookResult("not JSON", notebookSources(document()), 0)).toThrow();
    expect(() => parseNotebookResult(JSON.stringify({ ...response, sections: [response.sections[0], response.sections[0]] }), notebookSources(document()), 0)).toThrow();
  });
  it("allows an honest insufficient-evidence result without manufacturing sources", () => {
    expect(parseNotebookResult('{"insufficient":true,"sections":[],"actions":[]}', notebookSources(document()), 0).insufficient).toBe(true);
    expect(() => parseNotebookResult(JSON.stringify({ ...response, insufficient: true }), notebookSources(document()), 0)).toThrow();
  });
  it("exports tracked commitments' own evidence after the AI snapshot changes", () => {
    const note = document();
    note.commitments = [{ id: crypto.randomUUID(), title: "Send a draft", owner: "Alex", when: "Friday", done: false, sources: [{ id: "T1", kind: "transcript", text: "Original commitment evidence" }] }];
    note.enhancement = parseNotebookResult(JSON.stringify(response), notebookSources(note), 0);
    note.revision = 2;
    const output = exportNotebook(note);
    expect(output).toContain("Original commitment evidence");
    expect(output).toContain("sources have since changed");
    expect(output).toContain(note.notes);
    expect(output).toContain("[ ] Send a draft");
  });
  it("validates ownership and bounds in stored document shape", () => {
    expect(notebookDocumentSchema.safeParse(document()).success).toBe(true);
    expect(notebookDocumentSchema.safeParse({ ...document(), ownerId: "guest" }).success).toBe(false);
    expect(notebookDocumentSchema.safeParse({ ...document(), notes: "x".repeat(60001) }).success).toBe(false);
  });
});
