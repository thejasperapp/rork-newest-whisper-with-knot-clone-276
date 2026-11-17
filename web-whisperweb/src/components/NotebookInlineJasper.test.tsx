import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { newNotebookDocument, type NotebookResult } from "@/lib/notebookDocument";
import { runNotebookIntelligence } from "@/lib/notebookIntelligence";
import { NotebookInlineJasper } from "./NotebookInlineJasper";
vi.mock("@/hooks/useChatOperationGuard", () => ({ useChatOperationGuard: () => () => () => {} }));
vi.mock("@/lib/notebookIntelligence", () => ({ runNotebookIntelligence: vi.fn() }));
const note = { ...newNotebookDocument("00000000-0000-4000-8000-000000000001"), notes: "Keep this. Do not send this.", transcript: "Do not send this transcript." };
const selection = { kind: "notes" as const, start: 0, end: 10, text: "Keep this.", revision: 0 };
const result: NotebookResult = { insufficient: false, actions: [], sections: [{ title: "Key passages", items: [{ text: "Keep this.", sourceIds: ["N1"] }] }], sources: [{ id: "N1", kind: "notes", text: "Keep this." }], generatedAt: "2026-09-12T08:00:00Z", revision: 0 };
function setup() {
  const highlight = vi.fn(), keep = vi.fn(), client = new QueryClient();
  const content = (revision = 0) => <QueryClientProvider client={client}><NotebookInlineJasper document={{ ...note, revision }} selection={selection} onHighlight={highlight} onKeep={keep} /></QueryClientProvider>;
  const view = render(content()); return { ...view, highlight, keep, content };
}
beforeEach(() => { vi.mocked(runNotebookIntelligence).mockReset().mockResolvedValue(result); });
afterEach(cleanup);
describe("inline Jasper scope and review", () => {
  it("highlights locally without AI, even before any cloud consent", () => {
    const { highlight } = setup(); fireEvent.click(screen.getByRole("button", { name: "Highlight" }));
    expect(highlight).toHaveBeenCalledWith(expect.objectContaining({ text: "Keep this.", start: 0, end: 10, origin: "manual" }));
    expect(runNotebookIntelligence).not.toHaveBeenCalled();
  });
  it("sends only selected evidence after first-use consent and retains only after review", async () => {
    const { keep } = setup(); fireEvent.click(screen.getByRole("button", { name: "Enhance" }));
    expect(runNotebookIntelligence).not.toHaveBeenCalled(); fireEvent.click(screen.getByRole("button", { name: "Continue with Jasper" }));
    await screen.findByRole("button", { name: "Keep draft & review follow-ups" });
    expect(runNotebookIntelligence).toHaveBeenCalledWith(note, null, expect.any(Function), expect.any(AbortSignal), result.sources, "enhance");
    expect(keep).not.toHaveBeenCalled(); fireEvent.click(screen.getByRole("button", { name: "Keep draft & review follow-ups" })); expect(keep).toHaveBeenCalledWith(result);
    fireEvent.click(screen.getByRole("button", { name: "Summarize" }));
    await waitFor(() => expect(runNotebookIntelligence).toHaveBeenCalledTimes(2)); expect(screen.queryByRole("alertdialog")).not.toBeInTheDocument();
  });
  it("retains a frozen response when writing changes during generation", async () => {
    let finish!: (value: NotebookResult) => void;
    vi.mocked(runNotebookIntelligence).mockImplementation(() => new Promise((resolve) => { finish = resolve; }));
    const view = setup(); fireEvent.click(screen.getByRole("button", { name: "Enhance" })); fireEvent.click(screen.getByRole("button", { name: "Continue with Jasper" }));
    await waitFor(() => expect(runNotebookIntelligence).toHaveBeenCalled()); view.rerender(view.content(1));
    await act(async () => finish(result)); expect(await screen.findByText(/writing has since changed/)).toBeInTheDocument(); expect(view.keep).not.toHaveBeenCalled();
  });
  it("suggested highlights require exact quote evidence and explicit acceptance", async () => {
    const { highlight } = setup(); fireEvent.click(screen.getByRole("button", { name: "Find key points" })); fireEvent.click(screen.getByRole("button", { name: "Continue with Jasper" }));
    fireEvent.click(await screen.findByRole("button", { name: "Keep highlight" })); expect(highlight).toHaveBeenCalledWith(expect.objectContaining({ origin: "jasper", text: "Keep this." }));
  });
});
