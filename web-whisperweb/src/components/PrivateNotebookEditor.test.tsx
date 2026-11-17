import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { newNotebookDocument, type NotebookDocument } from "@/lib/notebookDocument";
import { listNotebookRecoveries } from "@/lib/notebookRecovery";
import { saveNotebookDocument } from "@/lib/notebookStorage";
import { PrivateNotebookEditor } from "./PrivateNotebookEditor";

vi.mock("@/hooks/useChatOperationGuard", () => ({ useChatOperationGuard: () => () => () => {} }));
vi.mock("@/lib/notebookStorage", () => ({ saveNotebookDocument: vi.fn() }));
vi.mock("@/lib/notebookIntelligence", () => ({ runNotebookIntelligence: vi.fn() }));
const ownerId = "11d2d71c-f84a-4ab1-95bd-dd1a87a2c001";
function editor(): ReturnType<typeof render> {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  return render(<QueryClientProvider client={client}><PrivateNotebookEditor initial={newNotebookDocument(ownerId)} onClose={() => {}} onSaved={() => {}} /></QueryClientProvider>);
}
beforeEach(() => {
  localStorage.clear();
  vi.mocked(saveNotebookDocument).mockReset().mockImplementation(async (document) => ({ ...document, storageRevision: document.storageRevision + 1 }));
});
afterEach(() => cleanup());
describe("notebook editor draft safety", () => {
  it("switches between enhanced and original notes without changing the saved writing", async () => {
    const note = { ...newNotebookDocument(ownerId), notes: "My original wording.", enhancement: { insufficient: false, sections: [{ title: "Launch", items: [{ text: "Enhanced recap.", sourceIds: ["T1"] }] }], actions: [], revision: 0, generatedAt: "2026-09-13T01:00:00Z", sources: [{ id: "T1", kind: "transcript" as const, text: "A launch discussion." }] } };
    const client = new QueryClient();
    render(<QueryClientProvider client={client}><PrivateNotebookEditor initial={note} sidekickMode onClose={() => {}} onSaved={() => {}} /></QueryClientProvider>);
    expect(await screen.findByText("Enhanced recap.")).toBeVisible();
    fireEvent.change(screen.getByLabelText("Notes version"), { target: { value: "original" } });
    expect(screen.getByLabelText("My original notes")).toHaveValue("My original wording.");
    expect(saveNotebookDocument).not.toHaveBeenCalled();
  });
  it("does not turn an acknowledged note into a local-error badge because another note failed", () => {
    const note = { ...newNotebookDocument(ownerId), cloudRevision: 2, storageRevision: 3, syncedStorageRevision: 3 };
    render(<QueryClientProvider client={new QueryClient()}><PrivateNotebookEditor initial={note} syncError="Another note needs attention" onClose={() => {}} onSaved={() => {}} /></QueryClientProvider>);
    expect(screen.getByText(/Saved to account/)).toBeVisible();
    expect(screen.queryByText("Another note needs attention")).toBeNull();
  });
  it("retains unsaved writing when navigation unmounts the editor before autosave", () => {
    const view = editor();
    fireEvent.change(screen.getByLabelText("My original notes"), { target: { value: "The last keystroke survives" } });
    view.unmount();
    expect(saveNotebookDocument).not.toHaveBeenCalled();
    expect(listNotebookRecoveries(ownerId)[0].document.notes).toBe("The last keystroke survives");
  });
  it("clears its recovery only after persistence succeeds", async () => {
    editor();
    fireEvent.change(screen.getByLabelText("My original notes"), { target: { value: "Saved writing" } });
    expect(listNotebookRecoveries(ownerId)).toHaveLength(1);
    await waitFor(() => expect(saveNotebookDocument).toHaveBeenCalledTimes(1), { timeout: 2500 });
    await waitFor(() => expect(listNotebookRecoveries(ownerId)).toHaveLength(0));
  });
  it("keeps newer edits and advances the storage revision after an earlier save completes", async () => {
    let complete!: (value: NotebookDocument) => void;
    vi.mocked(saveNotebookDocument).mockImplementationOnce(() => new Promise<NotebookDocument>((resolve) => { complete = resolve; }));
    editor();
    fireEvent.change(screen.getByLabelText("My original notes"), { target: { value: "First edit" } });
    await waitFor(() => expect(saveNotebookDocument).toHaveBeenCalledTimes(1), { timeout: 2500 });
    const first = vi.mocked(saveNotebookDocument).mock.calls[0][0];
    fireEvent.change(screen.getByLabelText("My original notes"), { target: { value: "Second edit" } });
    await act(async () => { complete({ ...first, storageRevision: 1 }); });
    expect(listNotebookRecoveries(ownerId)[0].document.notes).toBe("Second edit");
    await waitFor(() => expect(saveNotebookDocument).toHaveBeenCalledTimes(2), { timeout: 2500 });
    expect(vi.mocked(saveNotebookDocument).mock.calls[1][0]).toMatchObject({ notes: "Second edit", storageRevision: 1 });
  });
});
