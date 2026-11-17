import { StrictMode, type ReactNode } from "react";
import { act, cleanup, renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { ConversationSummaryPage } from "@/lib/conversationSummaries";
const mocks = vi.hoisted(() => ({ fetch: vi.fn() }));
vi.mock("@/lib/conversationSummaries", async importOriginal => ({
  ...await importOriginal<typeof import("@/lib/conversationSummaries")>(), fetchConversationSummaries: mocks.fetch,
}));
import { useConversationSummaries } from "./useConversationSummaries";

const page = (name: string, more = false): ConversationSummaryPage => ({ conversations: [{ otherUserId: name, kind: "direct", otherUsername: name, otherProfile: null, lastMessage: name, lastDate: null, lastFromMe: false, unread: 1, messages: [] }], next: more ? { id: name, createdAt: null } : null });
const clients: QueryClient[] = [];
function context(strict = false) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } }); clients.push(client);
  return { client, wrapper: ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{strict ? <StrictMode>{children}</StrictMode> : children}</QueryClientProvider> };
}
afterEach(() => { cleanup(); clients.forEach(client => client.clear()); clients.length = 0; vi.resetAllMocks(); });

describe("inbox summary query ownership", () => {
  it("recovers from Strict Mode cancellation without leaving the inbox stuck", async () => {
    mocks.fetch.mockImplementation(async (_owner, _cursor, signal: AbortSignal) => {
      if (signal.aborted) throw new Error("cancelled");
      return page("ready");
    });
    const { wrapper } = context(true);
    const hook = renderHook(() => useConversationSummaries("A"), { wrapper });
    await waitFor(() => expect(hook.result.current.conversations[0]?.otherUsername).toBe("ready"));
  });
  it("keeps loaded pages during a temporary failure and retries the same continuation", async () => {
    mocks.fetch.mockResolvedValueOnce(page("newest", true)).mockRejectedValue(new Error("offline"));
    const { wrapper } = context();
    const hook = renderHook(() => useConversationSummaries("A"), { wrapper });
    await waitFor(() => expect(hook.result.current.conversations).toHaveLength(1));
    await act(async () => { await hook.result.current.fetchNextPage(); });
    expect(hook.result.current.isFetchNextPageError).toBe(true);
    expect(hook.result.current.conversations.map(c => c.otherUsername)).toEqual(["newest"]);
    mocks.fetch.mockResolvedValueOnce(page("quiet"));
    await act(async () => { await hook.result.current.fetchNextPage(); });
    expect(mocks.fetch.mock.calls[mocks.fetch.mock.calls.length - 1]?.[1]).toEqual({ id: "newest", createdAt: null });
    expect(hook.result.current.conversations.map(c => c.otherUsername)).toEqual(["newest", "quiet"]);
  });
  it("aborts outgoing work and shows neither old rows nor a late result in the next account", async () => {
    let finish!: (value: ConversationSummaryPage) => void;
    let outgoing: AbortSignal | undefined;
    mocks.fetch.mockImplementationOnce((_owner, _cursor, signal) => { outgoing = signal; return new Promise(resolve => { finish = resolve; }); })
      .mockResolvedValue(page("B-only"));
    const { wrapper } = context();
    const hook = renderHook(({ owner }) => useConversationSummaries(owner), { wrapper, initialProps: { owner: "A" } });
    await waitFor(() => expect(outgoing).toBeDefined());
    hook.rerender({ owner: "B" });
    await waitFor(() => expect(hook.result.current.conversations[0]?.otherUsername).toBe("B-only"));
    expect(outgoing?.aborted).toBe(true);
    await act(async () => { finish(page("A-private")); });
    expect(hook.result.current.conversations.map(c => c.otherUsername)).toEqual(["B-only"]);
  });
});
