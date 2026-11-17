import "fake-indexeddb/auto";
import { act, cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { NotebookQuestions } from "./NotebookQuestions";
import { runNotebookIntelligence } from "@/lib/notebookIntelligence";
import { newNotebookDocument, parseNotebookResult, type NotebookDocument, type NotebookResult, type NotebookSource } from "@/lib/notebookDocument";
import { listNotebookDocuments, saveNotebookDocument } from "@/lib/notebookStorage";
import type { NotebookWorkflow } from "@/lib/notebookWorkflow";

vi.mock("@/lib/supabase", () => ({ supabase: { auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }) } } }));
vi.mock("@/lib/notebookIntelligence", () => ({ runNotebookIntelligence: vi.fn() }));
const check = (): void => {};
function result(sources: NotebookSource[], actions = false): NotebookResult {
  return parseNotebookResult(JSON.stringify({ insufficient: false, sections: [{ title: "Test result", items: [{ text: "Supported synthesis", sourceIds: [sources[0].id] }] }], actions: actions ? [{ title: "Review the launch", owner: "Alex", when: "Friday", sourceIds: [sources[0].id] }] : [] }), sources, 0);
}
async function notes(): Promise<NotebookDocument[]> {
  const owner = crypto.randomUUID(), meeting = crypto.randomUUID();
  return Promise.all(["First source", "Second source", "Unselected sibling"].map((title) => saveNotebookDocument({ ...newNotebookDocument(owner, meeting, title), notes: `${title}: Alex will review the launch Friday.` }, check)));
}
function setup(documents: NotebookDocument[]): { show: (documents: NotebookDocument[], disabled?: boolean) => void; client: QueryClient } {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  const owner = documents[0].ownerId;
  const ui = (picked: NotebookDocument[], disabled = false): JSX.Element => <QueryClientProvider client={client}><NotebookQuestions ownerId={owner} documents={picked} disabled={disabled} /></QueryClientProvider>;
  const view = render(ui(documents));
  return { show: (picked, disabled) => view.rerender(ui(picked, disabled)), client };
}
function request(label: string): void {
  fireEvent.click(screen.getByRole("button", { name: label }));
  if (label === "Ask") fireEvent.change(screen.getByLabelText("Question across selected notes"), { target: { value: "What is next?" } });
  fireEvent.click(screen.getByRole("checkbox"));
  fireEvent.click(screen.getByRole("button", { name: `${label} with Jasper` }));
}
beforeEach(() => {
  vi.mocked(runNotebookIntelligence).mockReset().mockImplementation(async (_document, _question, _check, _signal, sources = [], workflow) => result(sources, workflow === "followups"));
});
afterEach(cleanup);

describe("selected-note Jasper workflows", () => {
  it.each<[string, NotebookWorkflow]>([["Ask", "ask"], ["Summarize", "summarize"], ["Compare", "compare"], ["Follow-ups", "followups"]])("%s sends only the central selection and an explicit task", async (label, task) => {
    const all = await notes(); setup(all.slice(0, 2));
    expect(screen.getAllByRole("checkbox")).toHaveLength(1);
    expect(runNotebookIntelligence).not.toHaveBeenCalled();
    request(label); await screen.findByText("Supported synthesis");
    await waitFor(() => expect(screen.getByRole("button", { name: `${label} with Jasper` })).toBeInTheDocument());
    const call = vi.mocked(runNotebookIntelligence).mock.calls[0];
    expect(call[5]).toBe(task);
    expect(call[4]?.map((source) => source.id)).toEqual(["M1-N1", "M2-N1"]);
    expect(JSON.stringify(call[4])).not.toContain("Unselected sibling");
    expect((await listNotebookDocuments(all[0].ownerId)).map((note) => note.storageRevision)).toEqual([1, 1, 1]);
    fireEvent.click(screen.getAllByText("Source M1-N1 · First source")[0]);
    expect(screen.getAllByText(/Saved revision 1/).length).toBeGreaterThan(0);
    expect(screen.getByText("2 selected · private")).toBeInTheDocument();
  });
  it("keeps an enhanced version in the selected note without replacing original writing", async () => {
    const all = await notes(); setup([all[0]]); request("Enhance"); await screen.findByText("Supported synthesis");
    fireEvent.click(screen.getByRole("button", { name: "Keep enhanced version in this note" }));
    await waitFor(async () => expect((await listNotebookDocuments(all[0].ownerId)).find((note) => note.id === all[0].id)?.enhancement).not.toBeNull());
    const stored = await listNotebookDocuments(all[0].ownerId), enhanced = stored.find((note) => note.id === all[0].id)!;
    expect(stored).toHaveLength(3); expect(enhanced.notes).toBe(all[0].notes); expect(enhanced.transcript).toBe(all[0].transcript); expect(enhanced.enhancement?.sources[0].id).toBe("M1-N1");
  });
  it("saves reviewed combined writing as a new account-saved note with source identities and immutable snapshots", async () => {
    const all = await notes(); setup(all.slice(0, 2)); request("Summarize"); await screen.findByText("Supported synthesis");
    fireEvent.click(screen.getByText("Edit & save a separate draft"));
    fireEvent.change(screen.getByLabelText("Editable combined draft"), { target: { value: "My reviewed brief" } });
    fireEvent.change(screen.getByLabelText("Combined draft title"), { target: { value: "Launch brief" } });
    fireEvent.click(screen.getByRole("button", { name: "Save as new note" }));
    await waitFor(async () => expect(await listNotebookDocuments(all[0].ownerId)).toHaveLength(4));
    const stored = await listNotebookDocuments(all[0].ownerId), brief = stored.find((note) => note.title === "Launch brief")!;
    expect(brief.notes).toContain("My reviewed brief"); expect(brief.notes).toContain(all[0].id); expect(brief.notes).toContain("[M2-N1]");
    expect(brief.syncEnabled).toBe(true); expect(brief.meetingId).toBeNull();
    for (const original of all) expect(stored.find((note) => note.id === original.id)).toEqual(original);
  });
  it("requires an explicit destination and reviewed fields, and never tracks into the first note by default", async () => {
    const all = await notes(); setup(all.slice(0, 2)); request("Follow-ups"); await screen.findByText("Supported synthesis");
    fireEvent.click(screen.getByRole("button", { name: "Review & track" }));
    const dialog = screen.getByRole("dialog");
    expect(within(dialog).getByRole("button", { name: "Track in chosen note" })).toBeDisabled();
    fireEvent.change(within(dialog).getByLabelText("Destination note"), { target: { value: all[1].id } });
    fireEvent.change(within(dialog).getByLabelText("Follow-up"), { target: { value: "Reviewed launch task" } });
    fireEvent.click(within(dialog).getByRole("button", { name: "Track in chosen note" }));
    await waitFor(() => expect(screen.queryByRole("dialog")).not.toBeInTheDocument());
    const stored = await listNotebookDocuments(all[0].ownerId);
    expect(stored.find((note) => note.id === all[0].id)?.commitments).toHaveLength(0);
    expect(stored.find((note) => note.id === all[1].id)?.commitments[0]).toMatchObject({ title: "Reviewed launch task", owner: "Alex", when: "Friday", done: false });
  });
  it("cancels an in-flight request when selection changes and never displays the late response", async () => {
    const all = await notes(); let complete!: (value: NotebookResult) => void;
    vi.mocked(runNotebookIntelligence).mockImplementation(() => new Promise((resolve) => { complete = resolve; }));
    const { show } = setup(all.slice(0, 2)); request("Summarize");
    await waitFor(() => expect(runNotebookIntelligence).toHaveBeenCalledOnce());
    const call = vi.mocked(runNotebookIntelligence).mock.calls[0]; show([all[1]]);
    expect(call[3].aborted).toBe(true);
    await act(async () => { complete(result(call[4]!)); });
    expect(screen.queryByText("Supported synthesis")).not.toBeInTheDocument(); expect(screen.getByRole("checkbox")).not.toBeChecked();
  });
  it("keeps edited output with its original source names after selection changes", async () => {
    const all = await notes(); const { show } = setup(all.slice(0, 2)); request("Summarize"); await screen.findByText("Supported synthesis");
    fireEvent.click(screen.getByText("Edit & save a separate draft"));
    fireEvent.change(screen.getByLabelText("Editable combined draft"), { target: { value: "Keep this reviewed writing" } });
    show([all[2]]);
    expect(screen.getByLabelText("Editable combined draft")).toHaveValue("Keep this reviewed writing");
    expect(screen.getByText(/Previous draft · not the current request/)).toHaveTextContent("First source · Second source");
    expect(screen.getByText("Source M1-N1 · First source")).toBeInTheDocument();
    expect(screen.getByRole("checkbox")).not.toBeChecked();
  });
  it("normalizes Enhance after multi-select and blocks empty, oversized or dirty sources", async () => {
    const all = await notes(); const { show } = setup([all[0]]);
    fireEvent.click(screen.getByRole("button", { name: "Enhance" })); show(all.slice(0, 2));
    await waitFor(() => expect(screen.getByRole("button", { name: "Summarize with Jasper" })).toBeInTheDocument());
    show([]); expect(screen.getByRole("checkbox")).toBeDisabled();
    show([{ ...all[0], notes: "a".repeat(24001) }]); expect(screen.getByRole("checkbox")).toBeDisabled();
    show([all[0]], true); expect(screen.getByRole("checkbox")).toBeDisabled();
    expect(runNotebookIntelligence).not.toHaveBeenCalled();
  });
});
