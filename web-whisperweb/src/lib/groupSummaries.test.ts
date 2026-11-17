import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Session } from "@supabase/supabase-js";
const mocks = vi.hoisted(() => ({ fetch: vi.fn(), session: vi.fn() }));
vi.mock("./supabase", async () => {
  const { createClient } = await import("@supabase/supabase-js");
  const client = createClient("https://summaries.invalid", "unit-test-key", {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }, global: { fetch: mocks.fetch },
  });
  vi.spyOn(client.auth, "getSession").mockImplementation(mocks.session);
  return { supabase: client };
});
import { fetchGroupSummaries, groupSummaryPage, groupSummaryInbox, uniqueGroupSummaries, type GroupSummary } from "./groupSummaries";
import { invalidateHistorySnapshot } from "./conversationHistory";
const owner = "11111111-1111-4111-8111-111111111111";
const group = "22222222-2222-4222-8222-222222222222";
const auth = (id: string) => ({ data: { session: { user: { id } } as Session }, error: null });
const row = (index = 0): GroupSummary => ({ group_id: index === 0 ? group : `group-${index}`,
  last_created_at: "2026-11-07T12:00:00.123456+00:00", last_message_id: `message-${index}`, unread_count: 160,
  last_message: { id: `message-${index}`, body: `::wg-v1::${group}::Friends: work::Hello`, from_user_id: owner,
    from_username: "me", to_user_id: group, to_username: "friend", created_at: "2026-11-07T12:00:00Z", read_at: null },
  participants: [{ user_id: group, username: "friend" }, { user_id: owner, username: "me" }, { user_id: "former-member", username: "former" }],
});
beforeEach(() => {
  mocks.session.mockResolvedValue(auth(owner));
  mocks.fetch.mockImplementation(async () => new Response("[]", { headers: { "Content-Type": "application/json" } }));
});
afterEach(() => vi.clearAllMocks());
describe("independent group inbox", () => {
  it("requests 50 summaries with raw microsecond cursor rather than raw history rows", async () => {
    const cursor = { id: owner, createdAt: "2026-11-07T12:00:00.123456+00:00" };
    await fetchGroupSummaries(owner, cursor);
    expect(String(mocks.fetch.mock.calls[0][0])).toContain("/rpc/whisper_group_summaries_v1");
    expect(JSON.parse(mocks.fetch.mock.calls[0][1].body)).toEqual({ p_limit: 50, p_before_at: cursor.createdAt, p_before_id: owner });
  });
  it("uses sentinel continuation before filtering and gives refreshed earlier pages precedence", () => {
    const rows = Array.from({ length: 51 }, (_, index) => row(index));
    const first = groupSummaryPage(rows);
    expect(first.groups).toHaveLength(50);
    expect(first.next).toEqual({ id: 'message-49', createdAt: rows[49].last_created_at });
    expect(groupSummaryPage(rows.slice(0,50)).next).toBeNull();
    const merged = uniqueGroupSummaries([first, { groups: [{ ...rows[0], unread_count: 1 }, rows[50]], next: null }]);
    expect(merged).toHaveLength(51);
    expect(merged[0].unread_count).toBe(160);
  });
  it("retains complete unread counts with outgoing latest, empty registry groups and authoritative rosters", () => {
    const registry = { id: group, name: "Verified", owner_id: owner, member_ids: [group], member_usernames: ["current"], business_id: null, created_at: null };
    const empty = { ...registry, id: "empty-group", name: "Empty" };
    const inbox = groupSummaryInbox(owner, [registry, empty], [row()]);
    expect(inbox.find(g => g.thread.id === group)).toMatchObject({ unread: 160, discovered: false, lastBody: "Hello", thread: { name: "Verified", member_ids: [group] } });
    expect(inbox.find(g => g.thread.id === empty.id)?.lastDate).toBeNull();
    const discovered = groupSummaryInbox(owner, [], [row()])[0];
    expect(discovered.discovered).toBe(true);
    expect(discovered.thread.member_ids).toEqual([group, "former-member"]);
  });
  it("rejects obsolete accounts and cancellation before requests", async () => {
    mocks.session.mockResolvedValue(auth(group));
    await expect(fetchGroupSummaries(owner, null)).rejects.toThrow("account changed");
    mocks.session.mockResolvedValue(auth(owner));
    const controller = new AbortController(); controller.abort();
    await expect(fetchGroupSummaries(owner, null, controller.signal)).rejects.toThrow();
    expect(mocks.fetch).not.toHaveBeenCalled();
  });
  it("rejects outgoing-account and mutation responses rather than committing stale summaries", async () => {
    mocks.fetch.mockImplementationOnce(async () => {
      mocks.session.mockResolvedValue(auth(group));
      return new Response("[]");
    });
    await expect(fetchGroupSummaries(owner, null)).rejects.toThrow("account changed");
    mocks.session.mockResolvedValue(auth(owner));
    mocks.fetch.mockImplementationOnce(async () => { invalidateHistorySnapshot(); return new Response("[]"); });
    await expect(fetchGroupSummaries(owner, null)).rejects.toThrow("couldn't refresh");
  });
  it("does not convert transport failure into an empty inbox", async () => {
    mocks.fetch.mockImplementation(async () => new Response(JSON.stringify({ message: "unavailable" }), { status: 503 }));
    await expect(fetchGroupSummaries(owner, null)).rejects.toThrow("couldn't refresh");
  });
});
