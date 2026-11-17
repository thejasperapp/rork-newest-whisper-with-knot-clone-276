import { beforeEach, describe, expect, it } from "vitest";
import { newNotebookDocument } from "./notebookDocument";
import { clearNotebookRecovery, listNotebookRecoveries, retainNotebookRecovery } from "./notebookRecovery";

const ownerA = "11d2d71c-f84a-4ab1-95bd-dd1a87a2c001";
const ownerB = "11d2d71c-f84a-4ab1-95bd-dd1a87a2c002";
beforeEach(() => localStorage.clear());
describe("notebook recovery", () => {
  it("retains the last keystroke synchronously, before delayed autosave", () => {
    const document = { ...newNotebookDocument(ownerA), notes: "Unsaved writing" };
    retainNotebookRecovery(document, "editor-a");
    expect(listNotebookRecoveries(ownerA)[0].document.notes).toBe("Unsaved writing");
  });
  it("does not expose one account's recovery to another", () => {
    retainNotebookRecovery(newNotebookDocument(ownerA), "editor-a");
    expect(listNotebookRecoveries(ownerB)).toEqual([]);
  });
  it("clears only the saving editor, keeping another window's draft", () => {
    retainNotebookRecovery(newNotebookDocument(ownerA), "editor-a");
    retainNotebookRecovery(newNotebookDocument(ownerA), "editor-b");
    clearNotebookRecovery(ownerA, "editor-a");
    expect(listNotebookRecoveries(ownerA).map((item) => item.key)).toEqual(["editor-b"]);
  });
  it("rejects a mismatched owner inside a recovery without deleting it", () => {
    localStorage.setItem(`whisper-notebook-recovery:${ownerB}:bad`, JSON.stringify(newNotebookDocument(ownerA)));
    expect(listNotebookRecoveries(ownerB)).toEqual([]);
    expect(localStorage.length).toBe(1);
  });
});
