import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Session } from "@supabase/supabase-js";
import type { WhisperMessage } from "./types";
const mocks = vi.hoisted(() => ({ fetch: vi.fn(), session: vi.fn() }));
vi.mock("./supabase", async () => {
  const { createClient } = await import("@supabase/supabase-js");
  const client = createClient("https://history.invalid", "unit-test-key", {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }, global: { fetch: mocks.fetch },
  });
  vi.spyOn(client.auth, "getSession").mockImplementation(mocks.session);
  return { supabase: client };
});
import { fetchGroupHistory, groupHistoryPage } from "./groupHistory";
import { invalidateHistorySnapshot } from "./conversationHistory";
const owner = "11111111-1111-4111-8111-111111111111";
const group = "22222222-2222-4222-8222-222222222222";
const auth = (id: string) => ({ data: { session: { user: { id } } as Session }, error: null });
beforeEach(() => {
  mocks.session.mockResolvedValue(auth(owner));
  mocks.fetch.mockImplementation(async () => new Response("[]", { headers: { "Content-Type": "application/json" } }));
});
afterEach(() => vi.clearAllMocks());
describe("logical group history transport", () => {
  it("requests 100 recent or 50 older logical messages with lossless cursor parameters", async () => {
    await fetchGroupHistory(owner, group, null);
    expect(String(mocks.fetch.mock.calls[0][0])).toContain('/rpc/whisper_group_history_v1');
    expect(JSON.parse(mocks.fetch.mock.calls[0][1].body)).toEqual({ p_group_id: group, p_limit: 100 });
    await fetchGroupHistory(owner, group, { id: owner, createdAt: "2026-11-07T12:00:00.123456+00:00" });
    expect(JSON.parse(mocks.fetch.mock.calls[1][1].body)).toEqual({ p_group_id: group, p_limit: 50, p_before_id: owner, p_before_at: "2026-11-07T12:00:00.123456+00:00" });
  });
  it("retains full fanout and derives continuation before display deduplication", () => {
    const envelopes = Array.from({ length: 101 }, (_, index) => ({ cursor_at: "2026-11-07T12:00:00.123456Z", cursor_id: `cursor-${index}`,
      messages: Array.from({ length: 5 }, (_, recipient) => ({ id: `delivery-${index}-${recipient}` } as WhisperMessage)) }));
    const result = groupHistoryPage(envelopes, 100);
    expect(result.messages).toHaveLength(500);
    expect(result.next).toEqual({ id: "cursor-99", createdAt: envelopes[99].cursor_at });
    expect(result.messages.some(row => row.id.startsWith('delivery-100-'))).toBe(false);
    expect(groupHistoryPage(envelopes.slice(0,100), 100).next).toBeNull();
  });
  it("rejects outgoing accounts and cancellation before making requests", async () => {
    mocks.session.mockResolvedValue(auth(group));
    await expect(fetchGroupHistory(owner, group, null)).rejects.toThrow('account changed');
    expect(mocks.fetch).not.toHaveBeenCalled();
    mocks.session.mockResolvedValue(auth(owner));
    const controller = new AbortController(); controller.abort();
    await expect(fetchGroupHistory(owner, group, null, controller.signal)).rejects.toThrow();
    expect(mocks.fetch).not.toHaveBeenCalled();
  });
  it("rejects a response after an account switch", async () => {
    mocks.fetch.mockImplementationOnce(async () => {
      mocks.session.mockResolvedValue(auth(group));
      return new Response("[]", { headers: { "Content-Type": "application/json" } });
    });
    await expect(fetchGroupHistory(owner, group, null)).rejects.toThrow('account changed');
  });
  it("rejects stale SELECTs after an unsend, edit or read mutation", async () => {
    mocks.fetch.mockImplementationOnce(async () => {
      invalidateHistorySnapshot();
      return new Response("[]", { headers: { "Content-Type": "application/json" } });
    });
    await expect(fetchGroupHistory(owner, group, null)).rejects.toThrow("couldn't refresh");
  });
  it("never treats a network failure as authoritative empty history", async () => {
    mocks.fetch.mockResolvedValue(new Response(JSON.stringify({ message: "unavailable" }), { status: 503, headers: { "Content-Type": "application/json" } }));
    await expect(fetchGroupHistory(owner, group, null)).rejects.toThrow("couldn't refresh");
  });
});
