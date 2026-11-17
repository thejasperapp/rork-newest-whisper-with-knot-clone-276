import { StrictMode, type ReactNode } from "react";
import { act, cleanup, renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { MessagePage } from "@/lib/messageHistory";
import type { WhisperMessage } from "@/lib/types";
const mocks = vi.hoisted(() => ({ fetch: vi.fn() }));
vi.mock("@/lib/conversationHistory", () => ({ fetchConversationHistory: mocks.fetch }));
import { useConversationHistory } from "./useConversationHistory";

const row = (index: number): WhisperMessage => ({ id: String(index), body: String(index), from_user_id: "A", to_user_id: "peer", from_username: null, to_username: null, created_at: `2026-11-05T00:00:${String(index).padStart(2, "0")}Z`, read_at: null });
const clients: QueryClient[] = [];
function context(strict = false) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  clients.push(client);
  const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{strict ? <StrictMode>{children}</StrictMode> : children}</QueryClientProvider>;
  return { client, wrapper };
}
afterEach(() => { cleanup(); for (const client of clients) client.clear(); clients.length = 0; vi.resetAllMocks(); });

describe("conversation history viewing window", () => {
  it("trims older pages on close, keeping only the most recent page on reopening", async () => {
    const recent: MessagePage = { messages: [row(3), row(4)], next: { id: "cursor", createdAt: row(3).created_at } };
    const older: MessagePage = { messages: [row(1), row(2)], next: null };
    mocks.fetch.mockResolvedValueOnce(recent).mockResolvedValueOnce(older);
    const { client, wrapper } = context();
    const hook = renderHook(() => useConversationHistory("A", "peer", "direct"), { wrapper });
    await waitFor(() => expect(hook.result.current.messages).toHaveLength(2));
    await act(async () => { await hook.result.current.fetchNextPage(); });
    await waitFor(() => expect(hook.result.current.messages.map(message => message.id)).toEqual(["1", "2", "3", "4"]));
    hook.unmount();
    expect(client.getQueryData<{ pages: MessagePage[] }>(["conversations", "A", "history", "direct", "peer"])?.pages).toEqual([recent]);
    const reopened = renderHook(() => useConversationHistory("A", "peer", "direct"), { wrapper });
    expect(reopened.result.current.messages.map(message => message.id)).toEqual(["3", "4"]);
    expect(reopened.result.current.hasNextPage).toBe(true);
  });

  it("aborts outgoing history and never mixes it into the next account", async () => {
    let finish!: (page: MessagePage) => void;
    let signal: AbortSignal | undefined;
    mocks.fetch.mockImplementationOnce((_owner, _peer, _kind, _cursor, pendingSignal) => {
      signal = pendingSignal;
      return new Promise<MessagePage>(resolve => { finish = resolve; });
    }).mockResolvedValueOnce({ messages: [{ ...row(2), from_user_id: "B" }], next: null });
    const { wrapper } = context();
    const hook = renderHook(({ owner }) => useConversationHistory(owner, "peer", "direct"), { wrapper, initialProps: { owner: "A" } });
    await waitFor(() => expect(signal).toBeDefined());
    hook.rerender({ owner: "B" });
    await waitFor(() => expect(hook.result.current.messages[0]?.from_user_id).toBe("B"));
    expect(signal?.aborted).toBe(true);
    await act(async () => { finish({ messages: [row(1)], next: null }); });
    expect(hook.result.current.messages.map(message => message.from_user_id)).toEqual(["B"]);
  });

  it("recovers from Strict Mode's setup/cleanup cycle", async () => {
    mocks.fetch.mockImplementation(async (_owner, _peer, _kind, _cursor, signal: AbortSignal) => {
      if (signal.aborted) throw new Error("cancelled");
      return { messages: [row(1)], next: null };
    });
    const { wrapper } = context(true);
    const hook = renderHook(() => useConversationHistory("A", "peer", "direct"), { wrapper });
    await waitFor(() => expect(hook.result.current.isSuccess).toBe(true));
    expect(hook.result.current.messages.map(message => message.id)).toEqual(["1"]);
  });

  it("preserves last good content on a refresh error", async () => {
    mocks.fetch.mockResolvedValueOnce({ messages: [row(1)], next: null }).mockRejectedValue(new Error("offline"));
    const { wrapper } = context();
    const hook = renderHook(() => useConversationHistory("A", "peer", "direct"), { wrapper });
    await waitFor(() => expect(hook.result.current.isSuccess).toBe(true));
    await act(async () => { await hook.result.current.refetch(); });
    expect(hook.result.current.messages.map(message => message.id)).toEqual(["1"]);
    expect(hook.result.current.isError).toBe(true);
  });
});
