import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Session } from "@supabase/supabase-js";
const mocks = vi.hoisted(() => ({ fetch: vi.fn(), session: vi.fn(), profiles: vi.fn() }));
vi.mock("./supabase", async () => {
  const { createClient } = await import("@supabase/supabase-js");
  const client = createClient("https://summaries.invalid", "test-key", {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { fetch: mocks.fetch },
  });
  vi.spyOn(client.auth, "getSession").mockImplementation(mocks.session);
  return { supabase: client };
});
vi.mock("./api", () => ({ fetchProfilesByIds: mocks.profiles }));
import { fetchConversationSummaries, summaryWindow, uniqueConversations, type ThreadSummaryRow } from "./conversationSummaries";
import { invalidateHistorySnapshot } from "./conversationHistory";
const owner = "11111111-1111-4111-8111-111111111111";
const peer = "22222222-2222-4222-8222-222222222222";
const auth = (id: string) => ({ data: { session: { user: { id } } as Session }, error: null });
const row = (n: number): ThreadSummaryRow => ({ peer_id: peer, conversation_kind: "direct", last_message_id: String(n), last_body: `message ${n}`, last_created_at: "2026-11-07T00:00:00.123456Z", last_from_me: false, peer_username: "friend", unread_count: "130",
  last_message: { id: String(n), from_user_id: peer, to_user_id: owner, from_username: "friend", to_username: null, body: `message ${n}`, created_at: "2026-11-07T00:00:00.123456Z", read_at: null } });
const response = (rows: ThreadSummaryRow[]) => new Response(JSON.stringify(rows), { headers: { "Content-Type": "application/json" } });
beforeEach(() => {
  mocks.fetch.mockReset(); mocks.session.mockReset(); mocks.profiles.mockReset();
  mocks.session.mockResolvedValue(auth(owner)); mocks.profiles.mockResolvedValue({});
  mocks.fetch.mockResolvedValue(response([row(1)]));
});
afterEach(() => vi.clearAllMocks());

describe("paged inbox summary transport", () => {
  it("requests 50 summaries with a lossless raw cursor, then maps full unread totals and latest message", async () => {
    const cursor = { id: peer, createdAt: "2026-11-07T00:00:00.123456Z" };
    const page = await fetchConversationSummaries(owner, cursor);
    const [url, init] = mocks.fetch.mock.calls[0];
    expect(new URL(String(url)).pathname).toBe("/rest/v1/rpc/whisper_thread_summaries_v1");
    expect(JSON.parse(init.body)).toEqual({ p_limit: 50, p_before_at: cursor.createdAt, p_before_id: cursor.id });
    expect(page.conversations[0]).toMatchObject({ otherUserId: peer, otherUsername: "friend", unread: 130, messages: [row(1).last_message] });
    expect(page.next).toBeNull();
  });
  it("uses the 50th raw row, not a sentinel or a locally filtered result, for continuation", () => {
    const page = summaryWindow(Array.from({ length: 51 }, (_, n) => row(n + 1)));
    expect(page.rows).toHaveLength(50);
    expect(page.next).toEqual({ id: "50", createdAt: "2026-11-07T00:00:00.123456Z" });
    expect(summaryWindow(page.rows).next).toBeNull();
  });
  it("deduplicates by kind and peer while preserving the newer first-page version", async () => {
    const page = await fetchConversationSummaries(owner, null);
    const original = page.conversations[0];
    const unique = uniqueConversations([page, { conversations: [{ ...original, lastMessage: "older overlap" }, { ...original, kind: "dating" }], next: null }]);
    expect(unique.map(c => [c.kind, c.lastMessage])).toEqual([["direct", "message 1"], ["dating", "message 1"]]);
  });
  it("does not issue requests for an outgoing account or aborted work", async () => {
    mocks.session.mockResolvedValue(auth(peer));
    await expect(fetchConversationSummaries(owner, null)).rejects.toThrow("account changed");
    mocks.session.mockResolvedValue(auth(owner));
    const abort = new AbortController(); abort.abort();
    await expect(fetchConversationSummaries(owner, null, abort.signal)).rejects.toThrow("account changed");
    expect(mocks.fetch).not.toHaveBeenCalled();
  });
  it("rejects an account change during profile enrichment", async () => {
    mocks.profiles.mockImplementation(async () => { mocks.session.mockResolvedValue(auth(peer)); return {}; });
    await expect(fetchConversationSummaries(owner, null)).rejects.toThrow("account changed");
  });
  it("rejects a mutation arriving during enrichment instead of restoring an old preview or unread total", async () => {
    mocks.profiles.mockImplementation(async () => { invalidateHistorySnapshot(); return {}; });
    await expect(fetchConversationSummaries(owner, null)).rejects.toThrow("couldn't refresh");
  });
  it("reports transport/profile failures rather than an authoritative empty inbox", async () => {
    mocks.fetch.mockResolvedValueOnce(new Response(JSON.stringify({ message: "offline" }), { status: 503 }));
    await expect(fetchConversationSummaries(owner, null)).rejects.toThrow("couldn't refresh");
    mocks.profiles.mockRejectedValueOnce(new Error("People couldn't refresh"));
    await expect(fetchConversationSummaries(owner, null)).rejects.toThrow("People couldn't refresh");
  });
});
