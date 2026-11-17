import { describe, expect, it } from "vitest";
import { newNotebookDocument } from "./notebookDocument";
import { noteFile, sidekickSources, speechFile, type SidekickFile, type SidekickSpeech } from "./meetingSidekick";

const owner = "00000000-0000-4000-8000-000000000001";
const speech: SidekickSpeech = { id: "00000000-0000-4000-8000-000000000002", meeting_id: "00000000-0000-4000-8000-000000000003", text: "We moved launch to October.", username: "Alex", spoken_at: "2026-09-12T09:00:00Z" };
describe("explicit sidekick context", () => {
  it("combines live speech, current writing and a chosen past transcript without ID collisions", () => {
    const note = newNotebookDocument(owner); note.notes = "Check launch readiness.";
    const live = speechFile(speech.meeting_id, "Current meeting", [speech], "selected speech");
    const past = speechFile("00000000-0000-4000-8000-000000000004", "Past meeting", [{ ...speech, text: "We proposed September." }], "chosen past transcript");
    const result = sidekickSources([live, noteFile(note), past]);
    expect(result.map((source) => source.id)).toEqual(["M1-T1", "M2-N1", "M3-T1"]);
    expect(result[0].provenance).toContain("2026-09-12T09:00:00Z");
    expect(result[2].provenance).toContain("chosen past transcript");
    expect(result[0].text).toContain("Alex: We moved launch to October.");
  });
  it("retains a frozen snapshot after original writing changes", () => {
    const note = newNotebookDocument(owner); note.notes = "The original decision.";
    const selected = noteFile(note); note.notes = "Changed later.";
    expect(sidekickSources([selected])[0].text).toBe("The original decision.");
  });
  it("rejects duplicate items and more than eight items", () => {
    const file: SidekickFile = { id: "a", title: "A", sources: [{ id: "N1", kind: "notes", text: "Decision." }] };
    expect(() => sidekickSources([file, file])).toThrow(/unique/);
    expect(() => sidekickSources(Array.from({ length: 9 }, (_, index) => ({ ...file, id: String(index) })))).toThrow(/eight/);
  });
  it("rejects excess characters and passages instead of silently dropping evidence", () => {
    const sources = Array.from({ length: 21 }, (_, index) => ({ id: `N${index + 1}`, kind: "notes" as const, text: "x".repeat(1200) }));
    expect(() => sidekickSources([{ id: "long", title: "Long", sources }])).toThrow(/24,000/);
    expect(() => sidekickSources([{ id: "many", title: "Many", sources: Array.from({ length: 161 }, (_, index) => ({ id: `N${index + 1}`, kind: "notes", text: "x" })) }])).toThrow(/160/);
  });
  it("does not manufacture speech for an empty transcript", () => {
    expect(() => speechFile(speech.meeting_id, "Empty", [], "transcript so far")).toThrow();
  });
});
