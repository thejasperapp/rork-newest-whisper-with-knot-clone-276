import { afterEach, describe, expect, it, vi } from "vitest";
import { createNotebookDocumentIfAbsent } from "./notebookStorage";
import { attachFinalizedRecordingNote } from "./recordingNotebook";
vi.mock("./notebookStorage", () => ({ createNotebookDocumentIfAbsent: vi.fn() }));
afterEach(() => { vi.useRealTimers(); vi.resetAllMocks(); });
describe("recording attachment finalization", () => {
  it("bounds notebook storage wait and prevents a late write after timeout", async () => {
    vi.useFakeTimers();
    vi.mocked(createNotebookDocumentIfAbsent).mockImplementation(() => new Promise(() => {}));
    const result = attachFinalizedRecordingNote({ id: crypto.randomUUID(), ownerId: crypto.randomUUID(), meetingId: null, title: "Saved media", createdAt: new Date().toISOString(), status: "ready" });
    const rejected = expect(result).rejects.toThrow("timed out");
    await vi.advanceTimersByTimeAsync(3000); await rejected;
    const guard = vi.mocked(createNotebookDocumentIfAbsent).mock.calls[0][1];
    expect(guard).toThrow("timed out");
  });
});
