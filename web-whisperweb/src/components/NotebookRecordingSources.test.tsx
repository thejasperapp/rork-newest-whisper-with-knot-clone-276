import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { NotebookRecordingSources } from "./NotebookRecordingSources";
import { listRecordings } from "@/lib/meetingRecordingStorage";
import { listRecordingArchives, type RecordingArchive } from "@/lib/recordingCloud";
import { newNotebookDocument, type NotebookDocument } from "@/lib/notebookDocument";
import { meetingRecordingSchema, type MeetingRecording } from "@/lib/meetingRecordingModel";

vi.mock("@/lib/meetingRecordingStorage", () => ({ listRecordings: vi.fn() }));
vi.mock("@/lib/recordingCloud", () => ({ listRecordingArchives: vi.fn(), listRecordingArchivePage: async (...args: Parameters<typeof listRecordingArchives>) => ({ items: await listRecordingArchives(...args), issues: 0 }) }));
vi.mock("./MeetingRecordingLibrary", () => ({ RecordingPlayer: ({ record, embedded }: { record: MeetingRecording; embedded: boolean }) => <div role="region" aria-label="Local player" data-id={record.id} data-embedded={embedded} /> }));
vi.mock("./CloudRecordingLibrary", () => ({ CloudRecordingPlayer: ({ archive, embedded }: { archive: RecordingArchive; embedded: boolean }) => <div role="region" aria-label="Cloud player" data-id={archive.id} data-embedded={embedded} /> }));
const owner = "00000000-0000-4000-8000-000000000001";
function record(note: NotebookDocument, exact = true): MeetingRecording {
  return meetingRecordingSchema.parse({ version: 1, id: exact ? note.id : crypto.randomUUID(), ownerId: note.ownerId, meetingId: note.meetingId, title: exact ? "Exact recording" : "Related recording", duration: 30, createdAt: new Date().toISOString(), mimeType: "video/webm", status: "ready", cloudConsent: false, storageConsent: true, coverage: "Synthetic fixture", transcript: [], markers: [], warnings: [], revision: 1 });
}
function archive(record: MeetingRecording): RecordingArchive {
  return { id: crypto.randomUUID(), owner_id: record.ownerId, recording_id: record.id, source_revision: record.revision, snapshot: record, media_bytes: 100, audio_bytes: 100, state: "ready", created_at: new Date().toISOString() };
}
function setup(note: NotebookDocument): { client: QueryClient; imported: ReturnType<typeof vi.fn> } {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const imported = vi.fn();
  render(<QueryClientProvider client={client}><NotebookRecordingSources note={note} onImportTranscript={imported} /></QueryClientProvider>);
  return { client, imported };
}
beforeEach(() => { vi.mocked(listRecordings).mockReset().mockResolvedValue([]); vi.mocked(listRecordingArchives).mockReset().mockResolvedValue([]); });
afterEach(cleanup);
describe("video-first recording selection", () => {
  it("shows the exact browser recording immediately, even while cloud lookup is pending", async () => {
    const note = newNotebookDocument(owner), local = record(note);
    vi.mocked(listRecordings).mockResolvedValue([local]);
    vi.mocked(listRecordingArchives).mockImplementation(() => new Promise(() => {}));
    const { imported } = setup(note);
    expect(await screen.findByRole("region", { name: "Local player" })).toHaveAttribute("data-id", note.id);
    expect(screen.getByRole("region", { name: "Local player" })).toHaveAttribute("data-embedded", "true");
    expect(screen.queryByRole("combobox")).not.toBeInTheDocument();
    expect(imported).not.toHaveBeenCalled();
  });
  it("waits for exact lookup before showing an unrelated recording from the same meeting", async () => {
    const note = newNotebookDocument(owner, crypto.randomUUID()), exact = archive(record(note)), related = record(note, false);
    let resolveExact!: (items: RecordingArchive[]) => void;
    vi.mocked(listRecordings).mockResolvedValue([related]);
    vi.mocked(listRecordingArchives).mockImplementation(async (_owner, _signal, _cursor, _meeting, id) => id ? new Promise((resolve) => { resolveExact = resolve; }) : []);
    setup(note);
    await waitFor(() => expect(listRecordings).toHaveBeenCalled());
    expect(screen.queryByRole("region", { name: "Local player" })).not.toBeInTheDocument();
    await act(async () => { resolveExact([exact]); });
    expect(await screen.findByRole("region", { name: "Cloud player" })).toHaveAttribute("data-id", exact.id);
  });
  it("automatically shows and labels a meeting fallback when no exact recording exists", async () => {
    const note = newNotebookDocument(owner, crypto.randomUUID()), related = archive(record(note, false));
    vi.mocked(listRecordingArchives).mockImplementation(async (_owner, _signal, _cursor, _meeting, id) => id ? [] : [related]);
    setup(note);
    expect(await screen.findByRole("region", { name: "Cloud player" })).toHaveAttribute("data-id", related.id);
    expect(screen.getByText("Another recording from this meeting · Related recording")).toBeInTheDocument();
  });
  it("deduplicates exact snapshots and keeps the chosen source through background refresh", async () => {
    const note = newNotebookDocument(owner, crypto.randomUUID()), local = record(note), backup = archive(local);
    vi.mocked(listRecordings).mockResolvedValue([local]);
    vi.mocked(listRecordingArchives).mockResolvedValue([backup]);
    const { client } = setup(note);
    await screen.findByRole("combobox");
    expect(screen.getAllByRole("option")).toHaveLength(2);
    fireEvent.change(screen.getByRole("combobox"), { target: { value: `cloud:${backup.id}` } });
    expect(screen.getByRole("region", { name: "Cloud player" })).toHaveAttribute("data-id", backup.id);
    await act(async () => { await client.invalidateQueries({ queryKey: ["recordings", owner] }); });
    expect(screen.getByRole("region", { name: "Cloud player" })).toHaveAttribute("data-id", backup.id);
  });
  it("does not display recordings from a different owner or meeting", async () => {
    const note = newNotebookDocument(owner, crypto.randomUUID());
    vi.mocked(listRecordings).mockResolvedValue([{ ...record(note), ownerId: crypto.randomUUID() }, { ...record(note, false), meetingId: crypto.randomUUID() }]);
    vi.mocked(listRecordingArchives).mockResolvedValue([archive({ ...record(note), ownerId: crypto.randomUUID() })]);
    setup(note);
    await screen.findByText(/No video available/);
    expect(screen.queryByRole("region")).not.toBeInTheDocument();
  });
  it("resolves an attached recording by recording UUID rather than the recap note UUID", async () => {
    const note = newNotebookDocument(owner, crypto.randomUUID()), attached = record(note, false), unrelated = record(note, false);
    note.recordingIds = [attached.id];
    const backup = archive(attached);
    vi.mocked(listRecordings).mockResolvedValue([unrelated]);
    vi.mocked(listRecordingArchives).mockImplementation(async (_owner, _signal, _cursor, _meeting, id) => id === attached.id ? [backup] : []);
    setup(note);
    expect(await screen.findByRole("region", { name: "Cloud player" })).toHaveAttribute("data-id", backup.id);
    expect(screen.getByText("Attached recording")).toBeInTheDocument();
  });
  it("does not silently replace a missing attachment with a different meeting recording", async () => {
    const note = newNotebookDocument(owner, crypto.randomUUID()); note.recordingIds = [crypto.randomUUID()];
    const other = record(note, false); vi.mocked(listRecordings).mockResolvedValue([other]); setup(note);
    await screen.findByText(/attached recording\(s\) unavailable/);
    expect(screen.queryByRole("region", { name: "Local player" })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Browse other recordings from this meeting" }));
    expect(await screen.findByRole("region", { name: "Local player" })).toHaveAttribute("data-id", other.id);
    expect(screen.getByText(/Another recording from this meeting/)).toBeInTheDocument();
  });
  it("keeps local playback available if cloud lookup fails and exposes retry", async () => {
    const note = newNotebookDocument(owner);
    vi.mocked(listRecordings).mockResolvedValue([record(note)]);
    vi.mocked(listRecordingArchives).mockRejectedValue(new Error("Unavailable"));
    setup(note);
    expect(await screen.findByRole("region", { name: "Local player" })).toHaveAttribute("data-id", note.id);
    await screen.findByRole("button", { name: "Retry recordings" });
    vi.mocked(listRecordingArchives).mockResolvedValue([]);
    fireEvent.click(screen.getByRole("button", { name: "Retry recordings" }));
    await waitFor(() => expect(screen.queryByRole("button", { name: "Retry recordings" })).not.toBeInTheDocument());
    expect(screen.getByRole("region", { name: "Local player" })).toBeInTheDocument();
  });
});
