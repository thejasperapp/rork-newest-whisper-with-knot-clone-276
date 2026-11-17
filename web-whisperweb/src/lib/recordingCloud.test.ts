import { beforeEach, describe, expect, it, vi } from "vitest";
import type { UploadOptions, HttpRequest } from "tus-js-client";
import { meetingRecordingSchema, type MeetingRecording } from "./meetingRecordingModel";
const mocks = vi.hoisted(() => ({
  owner: "00000000-0000-4000-8000-000000000001", token: "test-token", onAuth: null as ((event: string, session: { user: { id: string } } | null) => void) | null,
  replies: [] as { data: unknown; error: unknown }[], options: [] as UploadOptions[], abort: vi.fn(), unsubscribe: vi.fn(), from: vi.fn(), list: vi.fn(), remove: vi.fn(), getSession: vi.fn(), headers: vi.fn(), xhrs: [] as XMLHttpRequest[], chunks: vi.fn(), media: vi.fn(), audio: vi.fn(),
}));
vi.mock("./supabase", () => ({ supabaseUrl: "https://example.supabase.co", supabase: {
  auth: { getSession: mocks.getSession, onAuthStateChange: (callback: typeof mocks.onAuth) => { mocks.onAuth = callback; return { data: { subscription: { unsubscribe: mocks.unsubscribe } } }; } },
  from: mocks.from,
  storage: { from: () => ({ list: mocks.list, remove: mocks.remove }) },
} }));
vi.mock("./meetingRecordingStorage", () => ({ recordingChunks: mocks.chunks }));
vi.mock("./recordingMedia", () => ({ recordingMedia: mocks.media }));
vi.mock("./recordingAudioBackup", () => ({ recordingAudioBackup: mocks.audio }));
vi.mock("tus-js-client", () => ({ Upload: class {
  constructor(_blob: Blob, private readonly options: UploadOptions) { mocks.options.push(options); }
  findPreviousUploads = async () => [];
  resumeFromPreviousUpload = vi.fn();
  abort = mocks.abort;
  start(): void { const xhr = new XMLHttpRequest(); mocks.xhrs.push(xhr); const request = { setHeader: mocks.headers, getUnderlyingObject: () => xhr } as unknown as HttpRequest; void Promise.resolve(this.options.onBeforeRequest?.(request)).then(() => this.options.onSuccess?.({} as never), () => this.options.onError?.(new Error("auth changed") as never)); }
} }));
import { backupRecording, deleteRecordingArchive, listRecordingArchives, listRecordingArchivePage, recordingArchiveSchema } from "./recordingCloud";
const record = (): MeetingRecording => meetingRecordingSchema.parse({ version: 1, id: crypto.randomUUID(), ownerId: mocks.owner, meetingId: null, title: "Test", duration: 2, createdAt: new Date().toISOString(), mimeType: "audio/mp4", status: "ready", cloudConsent: true, storageConsent: true, coverage: "Synthetic", transcript: [], markers: [], warnings: [], revision: 3 });
const archive = (r: MeetingRecording, state = "uploading") => ({ id: crypto.randomUUID(), owner_id: mocks.owner, recording_id: r.id, source_revision: r.revision, snapshot: r, media_bytes: 5, audio_bytes: 44, state, created_at: new Date().toISOString() });
beforeEach(() => {
  mocks.replies = []; mocks.options = []; mocks.xhrs = []; mocks.abort.mockReset().mockResolvedValue(undefined); mocks.unsubscribe.mockReset(); mocks.headers.mockReset();
  mocks.getSession.mockReset().mockImplementation(async () => ({ data: { session: { user: { id: mocks.owner }, access_token: mocks.token } } }));
  mocks.chunks.mockReset().mockResolvedValue([{}]); mocks.media.mockReset().mockResolvedValue(new Blob(["media"], { type: "audio/mp4" })); mocks.audio.mockReset().mockResolvedValue(new Blob([new Uint8Array(44)], { type: "audio/wav" })); mocks.list.mockReset().mockResolvedValue({ data: [], error: null }); mocks.remove.mockReset().mockResolvedValue({ data: [], error: null });
  mocks.from.mockReset().mockImplementation(() => { const reply = mocks.replies.shift() ?? { data: null, error: null }; const chain = { select: () => chain, eq: () => chain, order: () => chain, limit: () => chain, lt: () => chain, insert: () => chain, update: () => chain, delete: () => chain, abortSignal: () => chain, single: async () => reply, maybeSingle: async () => reply }; return chain; });
});
describe("private recording cloud operations", () => {
  it("filters meeting snapshots on the server for every page without dropping the owner boundary", async () => {
    const meetingId = crypto.randomUUID(), recordOne = { ...record(), meetingId }, row = archive(recordOne, "ready");
    const eq = vi.fn(), lt = vi.fn();
    mocks.from.mockImplementation(() => { const chain = { select: () => chain, eq: (...args: unknown[]) => { eq(...args); return chain; }, order: () => chain, limit: () => chain, lt: (...args: unknown[]) => { lt(...args); return chain; }, abortSignal: async () => ({ data: [row, archive(record(), "ready")], error: null }) }; return chain; });
    const first = await listRecordingArchives(mocks.owner, new AbortController().signal, undefined, meetingId);
    expect(first).toHaveLength(1); expect(first[0].snapshot.meetingId).toBe(meetingId);
    const second = await listRecordingArchives(mocks.owner, new AbortController().signal, row.created_at, meetingId);
    expect(second).toHaveLength(1); expect(eq.mock.calls).toEqual([["owner_id", mocks.owner], ["snapshot->>meetingId", meetingId], ["owner_id", mocks.owner], ["snapshot->>meetingId", meetingId]]);
    expect(lt).toHaveBeenCalledWith("created_at", row.created_at);
  });
  it("keeps valid recordings visible and pages past incompatible rows with equal timestamps", async () => {
    const valid = archive(record(), "ready");
    const rows = [valid, ...Array.from({ length: 29 }, () => ({ ...archive(record(), "ready"), snapshot: { broken: true }, created_at: valid.created_at }))];
    const or = vi.fn();
    mocks.from.mockImplementation(() => { const chain = { select: () => chain, eq: () => chain, order: () => chain, limit: () => chain, or: (value: string) => { or(value); return chain; }, abortSignal: async () => ({ data: rows, error: null }) }; return chain; });
    const page = await listRecordingArchivePage(mocks.owner, new AbortController().signal);
    expect(page.items).toEqual([recordingArchiveSchema.parse(valid)]); expect(page.issues).toBe(29);
    expect(page.nextCursor).toBe(`${rows[29].created_at}|${rows[29].id}`);
    await listRecordingArchivePage(mocks.owner, new AbortController().signal, page.nextCursor);
    expect(or).toHaveBeenCalledWith(expect.stringContaining(`id.lt.${rows[29].id}`));
  });
  it("never treats transcription approval as permanent storage approval", async () => { await expect(backupRecording({ ...record(), storageConsent: false }, new AbortController().signal, () => {}, () => {})).rejects.toThrow("permission"); expect(mocks.from).not.toHaveBeenCalled(); expect(mocks.options).toHaveLength(0); });
  it("does not reserve or send after pre-execution cancellation", async () => { const abort = new AbortController(); abort.abort(); await expect(backupRecording(record(), abort.signal, () => {}, () => {})).rejects.toThrow(); expect(mocks.chunks).not.toHaveBeenCalled(); expect(mocks.unsubscribe).toHaveBeenCalled(); });
  it("permanently cancels switching away and back during preparation", async () => { let finish!: () => void; mocks.chunks.mockImplementation(() => new Promise((resolve) => { finish = () => resolve([{}]); })); const promise = backupRecording(record(), new AbortController().signal, () => {}, () => {}); const rejected = expect(promise).rejects.toThrow(); await vi.waitFor(() => expect(mocks.chunks).toHaveBeenCalled()); mocks.onAuth?.("SIGNED_IN", { user: { id: crypto.randomUUID() } }); mocks.onAuth?.("SIGNED_IN", { user: { id: mocks.owner } }); finish(); await rejected; expect(mocks.from).not.toHaveBeenCalled(); });
  it("uploads both immutable objects before marking a snapshot ready", async () => { const r = record(), row = archive(r); mocks.replies.push({ data: null, error: null }, { data: row, error: null }, { data: { ...row, state: "ready" }, error: null }); const result = await backupRecording(r, new AbortController().signal, () => {}, () => {}); expect(result.state).toBe("ready"); expect(mocks.options).toHaveLength(2); expect(mocks.options[0].chunkSize).toBe(6291456); expect(mocks.options[0].endpoint).toBe("https://example.supabase.co/storage/v1/upload/resumable"); expect(mocks.options[0].metadata?.objectName).toBe(`${mocks.owner}/${row.id}/original`); expect(mocks.options[1].metadata?.objectName).toBe(`${mocks.owner}/${row.id}/audio.wav`); expect(mocks.headers).toHaveBeenCalledWith("Authorization", "Bearer test-token"); const error = vi.fn(); mocks.xhrs[0].onerror = error; mocks.xhrs[0].dispatchEvent(new ProgressEvent("timeout")); expect(error).toHaveBeenCalled(); });
  it("resumes a partially completed backup without sending the first object twice", async () => { const r = record(), row = archive(r); mocks.replies.push({ data: row, error: null }, { data: { ...row, state: "ready" }, error: null }); mocks.list.mockResolvedValueOnce({ data: [{ name: "original", metadata: { size: 5 } }], error: null }); await backupRecording(r, new AbortController().signal, () => {}, () => {}); expect(mocks.options).toHaveLength(1); expect(mocks.options[0].metadata?.objectName).toContain("audio.wav"); });
  it("retains an incomplete cloud row when media deletion fails", async () => { const row = recordingArchiveSchema.parse(archive(record(), "ready")); mocks.replies.push({ data: { id: row.id }, error: null }); mocks.remove.mockResolvedValue({ data: null, error: new Error("offline") }); await expect(deleteRecordingArchive(row, new AbortController().signal, () => {})).rejects.toThrow("incomplete"); expect(mocks.from).toHaveBeenCalledTimes(1); });
  it("rejects cross-account snapshots and missing archive consent", () => { const row = archive(record()); expect(recordingArchiveSchema.safeParse({ ...row, owner_id: crypto.randomUUID() }).success).toBe(false); expect(recordingArchiveSchema.safeParse({ ...row, snapshot: { ...row.snapshot, storageConsent: undefined } }).success).toBe(false); });
});
