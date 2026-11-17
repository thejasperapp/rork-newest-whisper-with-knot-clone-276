import "fake-indexeddb/auto";
import { act, cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { MemoryRouter } from "react-router-dom";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { PrivateNotebookWorkspace } from "./PrivateNotebookWorkspace";
import { newNotebookDocument } from "@/lib/notebookDocument";
import { ensureRecordingNote } from "@/lib/recordingNotebook";
import { deleteNotebookDocument, listNotebookDocuments, saveNotebookDocument } from "@/lib/notebookStorage";
import { listRecordings } from "@/lib/meetingRecordingStorage";
import { fetchNotebookArchive } from "@/lib/notebookArchive";
import type { WhisperMeeting } from "@/lib/meetings";
import type { MeetingRecording } from "@/lib/meetingRecordingModel";

vi.mock("@/lib/notebookArchive", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/lib/notebookArchive")>();
  return { ...actual, fetchNotebookArchive: vi.fn(), importArchivedMeetingNote: (...args: Parameters<typeof actual.importArchivedMeetingNote>) => actual.importArchivedMeetingNote(args[0], args[1], args[2], args[3], async () => {}) };
});
vi.mock("@/hooks/useChatOperationGuard", () => ({ useChatOperationGuard: () => () => () => {} }));
vi.mock("@/hooks/useNotebookSync", () => ({ useNotebookSync: () => ({ isPending: false, isError: false, data: "Local notes ready", mutate: () => {} }) }));
vi.mock("./NotebookQuestions", () => ({ NotebookQuestions: ({ documents }: { documents: { id: string }[] }) => <div data-testid="jasper-scope">{documents.map((note) => note.id).join(",")}</div> }));
vi.mock("./RecordingCloudBackupButton", () => ({ RecordingCloudBackupButton: () => null }));
vi.mock("@/lib/meetingRecordingStorage", () => ({ recordingReadIssues: () => 0, listRecordings: vi.fn(), recordingChunks: async () => [] }));
vi.mock("@/lib/recordingCloud", () => ({ listRecordingArchives: async () => [], listRecordingArchivePage: async () => ({ items: [], issues: 0 }), backupRecording: vi.fn() }));
vi.mock("@/lib/recordingMedia", () => ({ recordingMedia: async () => new Blob(["saved-media"], { type: "audio/wav" }) }));
vi.mock("@/lib/recordingAudioBackup", () => ({ recordingAudioBackup: async () => null }));

const check = (): void => {};
function record(ownerId: string): MeetingRecording {
  return { id: crypto.randomUUID(), ownerId, meetingId: crypto.randomUUID(), version: 1, title: "Recorded planning session", createdAt: new Date().toISOString(), lastWriteAt: Date.now(), duration: 30, mimeType: "video/webm", status: "ready", revision: 1, storageConsent: false, cloudConsent: false, coverage: "Synthetic test media", warnings: [], markers: [], transcript: [{ id: "p", start: 0, end: 30, text: "A source from the saved recording", timing: "chunk" }] };
}
function setup(owner: string, query = ""): ReturnType<typeof render> & { client: QueryClient } {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  const view = render(<MemoryRouter initialEntries={[`/notebook${query}`]}><QueryClientProvider client={client}><PrivateNotebookWorkspace key={owner} userId={owner} /></QueryClientProvider></MemoryRouter>);
  return { ...view, client };
}
beforeEach(() => {
  vi.mocked(fetchNotebookArchive).mockReset().mockResolvedValue({ meetings: [], hasMore: false });
  vi.mocked(listRecordings).mockReset().mockResolvedValue([]);
  vi.stubGlobal("URL", Object.assign(URL, { createObjectURL: vi.fn(() => "blob:retained-recording"), revokeObjectURL: vi.fn() }));
  localStorage.clear();
});
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });

describe("one selection-driven notebook", () => {
  it("opens a meeting-generated archive note with its recording and sends only its private copy to the workspace", async () => {
    const owner = crypto.randomUUID(), media = record(owner);
    const meeting = { id: media.meetingId!, title: "Archived kickoff", summary: "Sam will prepare the launch brief.", ended_at: "2026-09-12T12:00:00Z" } as WhisperMeeting;
    vi.mocked(fetchNotebookArchive).mockResolvedValue({ meetings: [meeting], hasMore: false }); vi.mocked(listRecordings).mockResolvedValue([media]);
    setup(owner); fireEvent.click(await screen.findByRole("button", { name: "Notes archive · from meetings" }));
    fireEvent.click(await screen.findByRole("button", { name: /Archived kickoff/ }));
    const dialog = screen.getByRole("dialog"), player = await within(dialog).findByRole("region", { name: "Recording playback" });
    await waitFor(() => expect(player.querySelector("video")).toHaveAttribute("src", "blob:retained-recording"));
    expect(await listNotebookDocuments(owner)).toHaveLength(0); expect(screen.getByTestId("jasper-scope")).toBeEmptyDOMElement();
    await within(dialog).findByLabelText(/Attach this recording/);
    fireEvent.click(within(dialog).getByRole("button", { name: "Use in Notebook" }));
    expect(await screen.findByLabelText("My original notes")).toHaveValue(meeting.summary);
    const note = (await listNotebookDocuments(owner))[0]; expect(note.recordingIds).toEqual([media.id]); expect(note.transcript).toBe("");
    expect(screen.getByTestId("jasper-scope")).toHaveTextContent(note.id); expect(await screen.findByText("Attached recording")).toBeInTheDocument();
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument(); expect(meeting.summary).toBe("Sam will prepare the launch brief.");
  });
  it("adds archive notes to the existing shared selection without including unchosen meetings", async () => {
    const owner = crypto.randomUUID(), first = await saveNotebookDocument({ ...newNotebookDocument(owner, null, "Current writing"), notes: "My notes" }, check);
    const meeting = { id: crypto.randomUUID(), title: "Chosen archive note", summary: "An agreed next step" } as WhisperMeeting;
    const other = { id: crypto.randomUUID(), title: "Unchosen archive note", summary: "Do not include this" } as WhisperMeeting;
    vi.mocked(fetchNotebookArchive).mockResolvedValue({ meetings: [meeting, other], hasMore: false });
    setup(owner); fireEvent.click(await screen.findByRole("button", { name: /Current writing My notes/ }));
    fireEvent.click(screen.getByRole("button", { name: "Add another meeting note from archive" }));
    fireEvent.click(await screen.findByRole("button", { name: /Chosen archive note/ }));
    fireEvent.click(screen.getByRole("button", { name: "Use in Notebook · add to selection" }));
    await waitFor(() => expect(screen.getByTestId("jasper-scope")).toHaveTextContent(`${first.id},${meeting.id}`));
    expect(screen.getByTestId("jasper-scope")).not.toHaveTextContent(other.id); expect(await listNotebookDocuments(owner)).toHaveLength(2);
    expect(screen.getByRole("heading", { name: "Working with 2 notes" })).toBeInTheDocument();
  });
  it("loads older archive pages and lets recordings play even when a private copy was deleted", async () => {
    const owner = crypto.randomUUID(), media = record(owner), meeting = { id: media.meetingId!, title: "Older archive note", summary: "Old recap text" } as WhisperMeeting;
    const copy = await saveNotebookDocument({ ...newNotebookDocument(owner, meeting.id), id: meeting.id, notes: "Deleted private writing" }, check); await deleteNotebookDocument(copy, check);
    vi.mocked(fetchNotebookArchive).mockImplementation(async (_owner, page) => ({ meetings: page ? [meeting] : [], hasMore: page === 0 })); vi.mocked(listRecordings).mockResolvedValue([media]);
    setup(owner); fireEvent.click(screen.getByRole("button", { name: "Notes archive · from meetings" }));
    fireEvent.click(await screen.findByRole("button", { name: "Load older meeting notes" }));
    fireEvent.click(await screen.findByRole("button", { name: /Older archive note/ }));
    await within(screen.getByRole("dialog")).findByRole("region", { name: "Recording playback" });
    fireEvent.click(screen.getByRole("button", { name: "Use in Notebook" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("private copy was deleted"); expect(await listNotebookDocuments(owner)).toHaveLength(0);
  });
  it("uses one shared selection across search and meetings, with no automatic sibling inclusion", async () => {
    const owner = crypto.randomUUID(), meeting = crypto.randomUUID();
    const first = await saveNotebookDocument(newNotebookDocument(owner, meeting, "Choose first"), check);
    const second = await saveNotebookDocument(newNotebookDocument(owner, meeting, "Choose second"), check);
    const sibling = await saveNotebookDocument(newNotebookDocument(owner, meeting, "Leave unselected"), check);
    setup(owner, `?meeting=${meeting}`);
    await screen.findByRole("button", { name: /Choose first Start writing/ });
    expect(screen.getByTestId("jasper-scope")).toHaveTextContent("");
    fireEvent.click(screen.getByRole("button", { name: "Select" }));
    fireEvent.click(screen.getByRole("button", { name: /Choose first Start writing/ }));
    fireEvent.click(screen.getByRole("button", { name: /Choose second Start writing/ }));
    expect(screen.getByTestId("jasper-scope")).toHaveTextContent(`${first.id},${second.id}`);
    expect(screen.getByTestId("jasper-scope")).not.toHaveTextContent(sibling.id);
    fireEvent.change(screen.getByLabelText("Search personal notebook"), { target: { value: "no matching rows" } });
    expect(screen.getByTestId("jasper-scope")).toHaveTextContent(`${first.id},${second.id}`);
    fireEvent.click(screen.getByRole("button", { name: "Clear" }));
    expect(screen.getByTestId("jasper-scope")).toBeEmptyDOMElement();
  });
  it("keeps a deleted recording note tombstoned while its media remains playable", async () => {
    const owner = crypto.randomUUID(), media = record(owner);
    const note = await ensureRecordingNote(media, check); await deleteNotebookDocument(note, check);
    vi.mocked(listRecordings).mockResolvedValue([media]); setup(owner, `?recording=${media.id}`);
    const player = await screen.findByRole("region", { name: "Recording playback" });
    await waitFor(() => expect(player.querySelector("video")).toHaveAttribute("src", "blob:retained-recording"));
    fireEvent.click(screen.getByRole("button", { name: "Start writing for this recording" }));
    await waitFor(() => expect(screen.getByRole("button", { name: "Start writing for this recording" })).not.toBeDisabled());
    expect(await listNotebookDocuments(owner)).toHaveLength(0);
    expect(player.querySelector("video")).not.toHaveAttribute("autoplay");
    expect(screen.queryByLabelText("Note title")).not.toBeInTheDocument();
  });
  it("opens recording media when the notebook is full without creating writing", async () => {
    const owner = crypto.randomUUID(), media = record(owner);
    await Promise.all(Array.from({ length: 200 }, (_, index) => saveNotebookDocument(newNotebookDocument(owner, null, `Note ${index}`), check)));
    vi.mocked(listRecordings).mockResolvedValue([media]); setup(owner, `?recording=${media.id}`);
    const player = await screen.findByRole("region", { name: "Recording playback" });
    await waitFor(() => expect(player.querySelector("video")).toHaveAttribute("src", "blob:retained-recording"));
    expect(await listNotebookDocuments(owner)).toHaveLength(200); expect(screen.queryByLabelText("Note title")).not.toBeInTheDocument();
  });
  it("opens the actual editor in the focus workspace without a dialog", async () => {
    const owner = crypto.randomUUID();
    const note = await saveNotebookDocument(newNotebookDocument(owner, null, "An inline note"), check);
    setup(owner); fireEvent.click(await screen.findByRole("button", { name: /An inline note Start writing/ }));
    const expanded = screen.getByRole("region", { name: "Expanded note" });
    expect(expanded.closest("article")).toHaveAttribute("aria-label", "Selected note workspace");
    expect(screen.getByLabelText("Note title")).toHaveValue(note.title);
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    fireEvent.keyDown(within(expanded).getByRole("button", { name: "Note options" }), { key: "Enter" });
    fireEvent.click(await screen.findByRole("menuitem", { name: "Collapse note" }));
    expect(screen.queryByRole("region", { name: "Expanded note" })).not.toBeInTheDocument();
  });
  it("does not switch away until autosave completes and keeps the active note through filtering", async () => {
    const owner = crypto.randomUUID();
    const first = await saveNotebookDocument(newNotebookDocument(owner, null, "First note"), check);
    await saveNotebookDocument(newNotebookDocument(owner, null, "Second note"), check);
    setup(owner); fireEvent.click(await screen.findByRole("button", { name: /First note Start writing/ }));
    fireEvent.change(screen.getByLabelText("My original notes"), { target: { value: "Do not drop the last keystroke" } });
    fireEvent.click(screen.getByRole("button", { name: /Second note Start writing/ }));
    expect(screen.getByLabelText("Note title")).toHaveValue("First note");
    fireEvent.change(screen.getByLabelText("Search personal notebook"), { target: { value: "no match" } });
    expect(screen.getByLabelText("My original notes")).toHaveValue("Do not drop the last keystroke");
    await waitFor(async () => expect((await listNotebookDocuments(owner)).find((note) => note.id === first.id)?.notes).toBe("Do not drop the last keystroke"), { timeout: 2500 });
    await waitFor(() => expect(screen.getByText(/Waiting for account confirmation/)).toBeInTheDocument());
    fireEvent.change(screen.getByLabelText("Search personal notebook"), { target: { value: "" } });
    fireEvent.click(screen.getByRole("button", { name: /Second note Start writing/ }));
    expect(screen.getByLabelText("Note title")).toHaveValue("Second note");
  });
  it("keeps unsaved writing mounted when another tab deletes its row without resurrecting the note", async () => {
    const owner = crypto.randomUUID();
    const note = await saveNotebookDocument(newNotebookDocument(owner, null, "Deleted elsewhere"), check);
    const { client } = setup(owner);
    fireEvent.click(await screen.findByRole("button", { name: /Deleted elsewhere Start writing/ }));
    fireEvent.change(screen.getByLabelText("My original notes"), { target: { value: "Keep this recovery visible" } });
    await act(async () => { await deleteNotebookDocument(note, check); await client.invalidateQueries({ queryKey: ["personal-notebook", owner] }); });
    expect(screen.getByLabelText("My original notes")).toHaveValue("Keep this recovery visible");
    expect(await screen.findByText(/This note is no longer listed/)).toBeInTheDocument();
    await waitFor(() => expect(screen.getByRole("button", { name: "Try saving again" })).toBeInTheDocument(), { timeout: 2500 });
    expect(await listNotebookDocuments(owner)).toEqual([]);
  });
  it("opens legacy recording deep links without creating a note, then explicitly starts writing and imports non-destructively", async () => {
    const owner = crypto.randomUUID(); const media = record(owner);
    vi.mocked(listRecordings).mockResolvedValue([media]);
    setup(owner, `?recording=${media.id}&meeting=${media.meetingId}&portal=workspace`);
    await screen.findByRole("region", { name: "Recording playback" });
    expect(await listNotebookDocuments(owner)).toHaveLength(0);
    expect(screen.queryByLabelText("Note title")).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Start writing for this recording" }));
    expect(await screen.findByLabelText("Note title")).toHaveValue(media.title);
    expect(await listNotebookDocuments(owner)).toHaveLength(1);
    expect(screen.getByLabelText("Pasted transcript")).toHaveValue("");
    const player = await screen.findByRole("region", { name: "Recording playback" });
    await waitFor(() => expect(player.querySelector("video")).toHaveAttribute("src", "blob:retained-recording"));
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    expect(player.querySelector("video")).not.toHaveAttribute("autoplay");
    expect(player.compareDocumentPosition(screen.getByLabelText("My original notes")) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(within(player).queryByRole("button", { name: "Use transcript in this note" })).not.toBeInTheDocument();
    expect(within(player).queryByRole("button", { name: "Hide player" })).not.toBeInTheDocument();
    fireEvent.click(within(player).getByRole("button", { name: "Recording options" }));
    fireEvent.click(within(player).getByRole("button", { name: "Use transcript in this note" }));
    expect(screen.getByLabelText("Pasted transcript")).toHaveValue("[0:00–0:30; approximate range] A source from the saved recording");
    fireEvent.change(screen.getByLabelText("Pasted transcript"), { target: { value: "My corrected source" } });
    fireEvent.click(within(player).getByRole("button", { name: "Use transcript in this note" }));
    expect(screen.getByLabelText("Pasted transcript")).toHaveValue("My corrected source");
    await waitFor(async () => expect((await listNotebookDocuments(owner))[0].transcript).toBe("My corrected source"), { timeout: 2500 });
    await act(async () => { expect((await ensureRecordingNote(media, check)).id).toBe(media.id); });
  });
});
