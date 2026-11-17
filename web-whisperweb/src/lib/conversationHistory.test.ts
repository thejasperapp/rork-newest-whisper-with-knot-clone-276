import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Session } from "@supabase/supabase-js";

const mocks = vi.hoisted(() => ({ fetch: vi.fn(), session: vi.fn() }));
vi.mock("./supabase", async () => {
  const { createClient } = await import("@supabase/supabase-js");
  const client = createClient("https://history.invalid", "unit-test-key", {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    global: { fetch: mocks.fetch },
  });
  vi.spyOn(client.auth, "getSession").mockImplementation(mocks.session);
  return { supabase: client };
});
vi.mock("./conversationIdentity", () => ({ conversationThreadId: async () => "33333333-3333-4333-8333-333333333333" }));
import { fetchConversationHistory, invalidateHistorySnapshot } from "./conversationHistory";

const owner = "11111111-1111-4111-8111-111111111111";
const peer = "22222222-2222-4222-8222-222222222222";
const dating = "33333333-3333-4333-8333-333333333333";
const auth = (id: string) => ({ data: { session: { user: { id } } as Session }, error: null });
beforeEach(() => { mocks.session.mockResolvedValue(auth(owner)); mocks.fetch.mockResolvedValue(new Response("[]", { headers: { "Content-Type": "application/json" } })); });
afterEach(() => { vi.clearAllMocks(); });

describe("scoped conversation transport", () => {
  it("keeps participant, kind, group/control exclusions and cursor together in one actual URL", async () => {
    await fetchConversationHistory(owner, peer, "direct", { id: peer, createdAt: "2026-11-05T00:00:00.123456Z" });
    const url = new URL(String(mocks.fetch.mock.calls[0][0]));
    const filters = url.searchParams.getAll("or");
    expect(filters).toHaveLength(1);
    expect(filters[0]).toContain(`and(from_user_id.eq.${owner},to_user_id.eq.${peer})`);
    expect(filters[0]).toContain(`and(from_user_id.eq.${peer},to_user_id.eq.${owner})`);
    expect(filters[0]).toContain("or(body.is.null,body.not.like.::wg-v1::%)");
    expect(filters[0]).toContain("or(body.is.null,body.not.like.::whisper-call-%)");
    expect(filters[0]).toContain(`or(thread_id.is.null,thread_id.neq.${dating})`);
    expect(filters[0]).toContain(`id.lt.${peer}`);
    expect(url.searchParams.get("limit")).toBe("51");
    expect(url.searchParams.get("order")).toBe("created_at.desc.nullslast,id.desc");
  });

  it("uses a separate dating identity and a recent-page sentinel", async () => {
    await fetchConversationHistory(owner, peer, "dating", null);
    const url = new URL(String(mocks.fetch.mock.calls[0][0]));
    expect(url.searchParams.get("or")).toContain(`thread_id.eq.${dating}`);
    expect(url.searchParams.get("or")).not.toContain("thread_id.neq");
    expect(url.searchParams.get("limit")).toBe("101");
  });

  it("rejects an outgoing account before networking", async () => {
    mocks.session.mockResolvedValue(auth(peer));
    await expect(fetchConversationHistory(owner, peer, "direct", null)).rejects.toThrow("account changed");
    expect(mocks.fetch).not.toHaveBeenCalled();
  });

  it("rejects a response if the account changed while it was in flight", async () => {
    // The real Supabase transport also consults auth while constructing its
    // Authorization header. Switch only when the HTTP response is delivered.
    mocks.fetch.mockImplementationOnce(async () => {
      mocks.session.mockResolvedValue(auth(peer));
      return new Response("[]", { headers: { "Content-Type": "application/json" } });
    });
    await expect(fetchConversationHistory(owner, peer, "direct", null)).rejects.toThrow("account changed");
  });

  it("rejects an old SELECT if an edit or unsend arrives before its response", async () => {
    mocks.fetch.mockImplementationOnce(async () => {
      invalidateHistorySnapshot();
      return new Response("[]", { headers: { "Content-Type": "application/json" } });
    });
    await expect(fetchConversationHistory(owner, peer, "direct", null)).rejects.toThrow("couldn't refresh");
  });

  it("rejects cancelled work without issuing a request", async () => {
    const controller = new AbortController(); controller.abort();
    await expect(fetchConversationHistory(owner, peer, "direct", null, controller.signal)).rejects.toThrow();
    expect(mocks.fetch).not.toHaveBeenCalled();
  });

  it("reports a temporary network failure rather than returning an authoritative empty page", async () => {
    mocks.fetch.mockResolvedValue(new Response(JSON.stringify({ message: "unavailable" }), { status: 503, headers: { "Content-Type": "application/json" } }));
    await expect(fetchConversationHistory(owner, peer, "direct", null)).rejects.toThrow("couldn't refresh");
  });
});
