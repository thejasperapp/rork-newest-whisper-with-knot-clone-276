import "fake-indexeddb/auto";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { WhisperMessage } from "./types";
const mocks = vi.hoisted(() => ({ session: vi.fn(), membership: vi.fn() }));
vi.mock("./supabase", () => ({ supabase: {
  auth: { getSession: mocks.session },
  from: () => { const query = { select() { return query; }, eq() { return query; }, limit() { return query; }, abortSignal() { return query; }, then(resolve: (value: unknown) => unknown, reject: (reason: unknown) => unknown) { return mocks.membership().then(resolve, reject); } }; return query; },
} }));
import { clearMessageSnapshots, currentMessageCacheRevision, loadMessageSnapshot, saveMessageSnapshot, setMessageCacheOwner } from "./messageCache";
import { conversationThreadId } from "./conversationIdentity";
const owner = "00000000-0000-0000-0000-000000000001";
const peer = "00000000-0000-0000-0000-000000000002";
const group = "00000000-0000-0000-0000-000000000003";
const scope = `direct:${peer}`;
const row: WhisperMessage = { id: "00000000-0000-0000-0000-000000000010", from_user_id: owner, to_user_id: peer, from_username: "owner", to_username: "peer", body: "Confirmed text", created_at: "2026-11-07T12:00:00Z", read_at: null };
const auth = (id: string | null) => ({ data: { session: id ? { user: { id } } : null } });
beforeEach(async () => {
  localStorage.clear();
  mocks.session.mockResolvedValue(auth(owner));
  mocks.membership.mockResolvedValue({ data: [{ owner_id: owner, member_ids: [] }], error: null });
  setMessageCacheOwner(owner);
  await clearMessageSnapshots(owner);
});
afterEach(async () => { await clearMessageSnapshots(owner); setMessageCacheOwner(null); vi.restoreAllMocks(); vi.clearAllMocks(); });
describe("authenticated message snapshot integration", () => {
  it("restores only for the current authenticated owner and keeps direct/dating separate", async () => {
    const dating = { ...row, thread_id: await conversationThreadId(owner, peer, "dating") };
    await saveMessageSnapshot(owner, scope, [row, dating], currentMessageCacheRevision());
    expect(await loadMessageSnapshot(owner, scope)).toEqual([row]);
    await saveMessageSnapshot(owner, `dating:${peer}`, [row, dating], currentMessageCacheRevision());
    expect(await loadMessageSnapshot(owner, `dating:${peer}`)).toEqual([dating]);
    mocks.session.mockResolvedValue(auth(peer));
    expect(await loadMessageSnapshot(owner, scope)).toEqual([]);
  });
  it("rejects in-flight responses after clear and sign-out", async () => {
    const before = currentMessageCacheRevision();
    await clearMessageSnapshots(owner);
    await saveMessageSnapshot(owner, scope, [row], before);
    expect(await loadMessageSnapshot(owner, scope)).toEqual([]);
    const signedIn = currentMessageCacheRevision();
    setMessageCacheOwner(null);
    await saveMessageSnapshot(owner, scope, [row], signedIn);
    setMessageCacheOwner(owner);
    expect(await loadMessageSnapshot(owner, scope)).toEqual([]);
  });
  it("does not redisplay a snapshot invalidated by another tab even before its deletion transaction", async () => {
    await saveMessageSnapshot(owner, scope, [row], currentMessageCacheRevision());
    expect(await loadMessageSnapshot(owner, scope)).toHaveLength(1);
    localStorage.setItem(`whisper.message-cache-epoch.v1:${owner}`, crypto.randomUUID());
    expect(await loadMessageSnapshot(owner, scope)).toEqual([]);
  });
  it("requires a fresh successful membership check and removes a revoked group's snapshot", async () => {
    const groupScope = `group:${group}`;
    const grouped = { ...row, body: `::wg-v1::${group}::Friends::Hello` };
    await saveMessageSnapshot(owner, groupScope, [grouped], currentMessageCacheRevision());
    expect(await loadMessageSnapshot(owner, groupScope)).toHaveLength(1);
    mocks.membership.mockResolvedValue({ data: null, error: { message: "Offline" } });
    expect(await loadMessageSnapshot(owner, groupScope)).toEqual([]);
    mocks.membership.mockResolvedValue({ data: [], error: null });
    expect(await loadMessageSnapshot(owner, groupScope)).toEqual([]);
    mocks.membership.mockResolvedValue({ data: [{ owner_id: owner, member_ids: [] }], error: null });
    expect(await loadMessageSnapshot(owner, groupScope)).toEqual([]);
  });
  it("rejects a membership response from the outgoing account", async () => {
    let finish!: (value: unknown) => void;
    mocks.membership.mockImplementationOnce(() => new Promise(resolve => { finish = resolve; }));
    const pending = saveMessageSnapshot(owner, `group:${group}`, [{ ...row, body: `::wg-v1::${group}::Friends::Hello` }], currentMessageCacheRevision());
    await vi.waitFor(() => expect(finish).toBeTypeOf("function"));
    setMessageCacheOwner(peer);
    finish({ data: [{ owner_id: owner, member_ids: [] }], error: null });
    await pending;
    setMessageCacheOwner(owner);
    expect(await loadMessageSnapshot(owner, `group:${group}`)).toEqual([]);
  });
  it("rejects cancelled reads and preserves confirmed server data when storage is unavailable", async () => {
    const abort = new AbortController(); abort.abort();
    await saveMessageSnapshot(owner, scope, [row], currentMessageCacheRevision(), abort.signal);
    expect(await loadMessageSnapshot(owner, scope, abort.signal)).toEqual([]);
    vi.spyOn(Storage.prototype, "getItem").mockImplementationOnce(() => { throw new Error("Storage unavailable"); });
    await expect(saveMessageSnapshot(owner, scope, [row], currentMessageCacheRevision())).resolves.toBeUndefined();
  });
});
