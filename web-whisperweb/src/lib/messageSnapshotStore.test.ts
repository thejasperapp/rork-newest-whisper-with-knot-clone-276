import "fake-indexeddb/auto";
import { afterEach, describe, expect, it, vi } from "vitest";
import { MessageSnapshotStore, snapshotRows } from "./messageSnapshotStore";
import type { WhisperMessage } from "./types";

const owner = "00000000-0000-0000-0000-000000000001";
const peer = "00000000-0000-0000-0000-000000000002";
const group = "00000000-0000-0000-0000-000000000003";
const id = (index: number) => `10000000-0000-0000-0000-${String(index).padStart(12, "0")}`;
const row = (index: number, body = "Confirmed text", recipient = peer): WhisperMessage => ({ id: id(index), from_user_id: owner, from_username: "owner", to_user_id: recipient, to_username: "peer", body, created_at: "2026-11-07T12:00:00Z", read_at: null });
afterEach(() => vi.restoreAllMocks());

describe("bounded private message snapshots", () => {
  it("keeps 100 confirmed text rows and drops private payloads and extra database columns", () => {
    const rows = Array.from({ length: 150 }, (_, index) => row(index));
    rows.push({ ...row(151), id: "local-pending" }, row(152, "::whisper-photo-v1::private"), row(153, "https://private.invalid"), { ...row(154), embed: { kind: "notes" } });
    rows.push({ ...row(155), media_url: "private://attachment" } as WhisperMessage);
    const kept = snapshotRows(rows, owner, `direct:${peer}`);
    expect(kept).toHaveLength(100);
    expect(kept[0].id).toBe(id(51));
    expect(kept.some(row => row.body.includes("::") || row.body.includes("https://") || row.id === "local-pending")).toBe(false);
    expect(JSON.stringify(kept)).not.toContain("private://attachment");
    expect(snapshotRows(rows, group, `direct:${peer}`)).toEqual([]);
  });

  it("retains whole sender-qualified group fanouts up to 100 logical messages", () => {
    const rows = Array.from({ length: 120 }, (_, index) => [0, 1, 2].map(copy => ({
      ...row(index * 3 + copy, `::wg-v1::${group}::Team: morning::Message ${index}`, id(900 + copy)),
      logical_group_message_id: id(1000 + index),
    }))).flat();
    const kept = snapshotRows(rows, owner, `group:${group}`);
    expect(kept).toHaveLength(300);
    expect(new Set(kept.map(row => row.logical_group_message_id)).size).toBe(100);
    for (const logical of new Set(kept.map(row => row.logical_group_message_id))) expect(kept.filter(row => row.logical_group_message_id === logical)).toHaveLength(3);
    expect(snapshotRows(rows, owner, `group:${peer}`)).toEqual([]);
  });

  it("isolates owners and rejects a delayed save after cache clearing", async () => {
    const store = new MessageSnapshotStore(`test-${crypto.randomUUID()}`);
    const lease = store.lease(owner);
    await store.save([row(1)], owner, `direct:${peer}`, lease);
    expect((await store.load(owner, `direct:${peer}`)).map(row => row.id)).toEqual([id(1)]);
    expect(await store.load(peer, `direct:${peer}`)).toEqual([]);
    expect(await store.clear(owner)).toBe(true);
    await store.save([row(2)], owner, `direct:${peer}`, lease);
    expect(await store.load(owner, `direct:${peer}`)).toEqual([]);
  });

  it("evicts the least recently opened conversation rather than the latest one", async () => {
    const store = new MessageSnapshotStore(`test-${crypto.randomUUID()}`, 3000);
    const now = vi.spyOn(Date, "now");
    const other = id(800), third = id(801);
    now.mockReturnValue(1000);
    await store.save([row(1, "a".repeat(700))], owner, `direct:${peer}`);
    now.mockReturnValue(2000);
    await store.save([row(2, "b".repeat(700), other)], owner, `direct:${other}`);
    now.mockReturnValue(3000);
    expect(await store.load(owner, `direct:${peer}`)).toHaveLength(1);
    now.mockReturnValue(4000);
    await store.save([row(3, "c".repeat(700), third)], owner, `direct:${third}`);
    expect(await store.load(owner, `direct:${other}`)).toEqual([]);
    expect(await store.load(owner, `direct:${peer}`)).toHaveLength(1);
    expect(await store.load(owner, `direct:${third}`)).toHaveLength(1);
  });

  it("rejects oversized snapshots and cross-tab stale writes at commit time", async () => {
    const store = new MessageSnapshotStore(`test-${crypto.randomUUID()}`, 400);
    await store.save([row(1, "x".repeat(1000))], owner, `direct:${peer}`);
    expect(await store.load(owner, `direct:${peer}`)).toEqual([]);
    const second = new MessageSnapshotStore(`test-${crypto.randomUUID()}`);
    await second.save([row(1)], owner, `direct:${peer}`, second.lease(owner), () => false);
    expect(await second.load(owner, `direct:${peer}`)).toEqual([]);
  });

  it("expires old snapshots without promoting them to current history", async () => {
    const now = vi.spyOn(Date, "now").mockReturnValue(1000);
    const store = new MessageSnapshotStore(`test-${crypto.randomUUID()}`);
    await store.save([row(1)], owner, `direct:${peer}`);
    now.mockReturnValue(1000 + 8 * 86_400_000);
    expect(await store.load(owner, `direct:${peer}`)).toEqual([]);
  });
});
