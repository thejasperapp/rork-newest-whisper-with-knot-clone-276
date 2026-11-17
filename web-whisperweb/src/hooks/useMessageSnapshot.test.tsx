import "fake-indexeddb/auto";
import { act, cleanup, renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { ReactNode } from "react";
import type { WhisperMessage } from "@/lib/types";
import type { MessagePage } from "@/lib/messageHistory";
const mocks = vi.hoisted(() => ({ session: vi.fn(), fetch: vi.fn() }));
vi.mock("@/lib/supabase", () => ({ supabase: { auth: { getSession: mocks.session } } }));
vi.mock("@/lib/conversationHistory", () => ({ fetchConversationHistory: mocks.fetch }));
import { clearMessageSnapshots, currentMessageCacheRevision, saveMessageSnapshot, setMessageCacheOwner } from "@/lib/messageCache";
import { useConversationHistory } from "./useConversationHistory";
const owner = "00000000-0000-0000-0000-000000000001", peer = "00000000-0000-0000-0000-000000000002";
const row: WhisperMessage = { id: "00000000-0000-0000-0000-000000000010", from_user_id: owner, to_user_id: peer, from_username: "owner", to_username: "peer", body: "Recent confirmed text", created_at: "2026-11-07T12:00:00Z", read_at: null };
let client: QueryClient;
function wrapper({ children }: { children: ReactNode }) { return <QueryClientProvider client={client}>{children}</QueryClientProvider>; }
beforeEach(async () => {
  client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  mocks.session.mockResolvedValue({ data: { session: { user: { id: owner } } } });
  mocks.fetch.mockImplementation(() => new Promise(() => {}));
  setMessageCacheOwner(owner);
  await clearMessageSnapshots(owner);
  await saveMessageSnapshot(owner, `direct:${peer}`, [row], currentMessageCacheRevision());
});
afterEach(async () => { cleanup(); client.clear(); await clearMessageSnapshots(owner); setMessageCacheOwner(null); vi.clearAllMocks(); });
describe("display-only history fallback", () => {
  it("shows recent text while the server is pending without inventing query success or a continuation", async () => {
    const hook = renderHook(() => useConversationHistory(owner, peer, "direct"), { wrapper });
    await waitFor(() => expect(hook.result.current.messages.map(row => row.id)).toEqual([row.id]));
    expect(hook.result.current.isPending).toBe(true);
    expect(hook.result.current.data).toBeUndefined();
    expect(hook.result.current.hasNextPage).toBe(false);
  });
  it("lets authoritative empty history remove cached text instead of resurrecting it", async () => {
    let finish!: (page: MessagePage) => void;
    mocks.fetch.mockImplementationOnce(() => new Promise<MessagePage>(resolve => { finish = resolve; }));
    const hook = renderHook(() => useConversationHistory(owner, peer, "direct"), { wrapper });
    await waitFor(() => expect(hook.result.current.messages).toHaveLength(1));
    await act(async () => finish({ messages: [], next: null }));
    await waitFor(() => expect(hook.result.current.isSuccess).toBe(true));
    expect(hook.result.current.messages).toEqual([]);
  });
  it("immediately hides outgoing and cross-tab-invalidated fallback text", async () => {
    const hook = renderHook(({ account }) => useConversationHistory(account, peer, "direct"), { wrapper, initialProps: { account: owner } });
    await waitFor(() => expect(hook.result.current.messages).toHaveLength(1));
    act(() => {
      const key = `whisper.message-cache-epoch.v1:${owner}`;
      localStorage.setItem(key, crypto.randomUUID());
      window.dispatchEvent(new StorageEvent("storage", { key }));
    });
    expect(hook.result.current.messages).toEqual([]);
    act(() => { setMessageCacheOwner(peer); mocks.session.mockResolvedValue({ data: { session: { user: { id: peer } } } }); });
    hook.rerender({ account: peer });
    expect(hook.result.current.messages).toEqual([]);
  });
});
