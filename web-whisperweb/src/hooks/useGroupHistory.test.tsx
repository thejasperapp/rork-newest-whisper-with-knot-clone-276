import { StrictMode, type ReactNode } from "react";
import { act, cleanup, renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { MessagePage } from "@/lib/messageHistory";
import type { WhisperMessage } from "@/lib/types";
const mocks = vi.hoisted(() => ({ fetch: vi.fn() }));
vi.mock("@/lib/groupHistory", () => ({ fetchGroupHistory: mocks.fetch }));
import { useGroupHistory } from "./useGroupHistory";
const row = (id: string): WhisperMessage => ({ id, body: id, from_user_id: "A", to_user_id: "peer", from_username: null, to_username: null, created_at: "2026-11-07T12:00:00Z", read_at: null });
const clients: QueryClient[] = [];
function context(strict = false) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } }); clients.push(client);
  const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{strict ? <StrictMode>{children}</StrictMode> : children}</QueryClientProvider>;
  return { client, wrapper };
}
afterEach(() => { cleanup(); clients.forEach(client => client.clear()); clients.length = 0; vi.resetAllMocks(); });

describe("group viewing window", () => {
  it("retains all recent fanout rows but trims older logical pages on close", async () => {
    const recent: MessagePage = { messages: [row('3'), row('4')], next: { id: 'cursor', createdAt: row('3').created_at } };
    mocks.fetch.mockResolvedValueOnce(recent).mockResolvedValueOnce({ messages: [row('1'), row('2')], next: null });
    const { client, wrapper } = context();
    const hook = renderHook(() => useGroupHistory('A','group'), { wrapper });
    await waitFor(() => expect(hook.result.current.messages).toHaveLength(2));
    await act(async () => { await hook.result.current.fetchNextPage(); });
    await waitFor(() => expect(hook.result.current.messages.map(r => r.id)).toEqual(['1','2','3','4']));
    hook.unmount();
    expect(client.getQueryData<{ pages: MessagePage[] }>(['group-wire','A','history','group'])?.pages).toEqual([recent]);
  });
  it("pauses hidden details, aborts outgoing work and resumes without losing good content", async () => {
    const { wrapper } = context();
    mocks.fetch.mockResolvedValueOnce({ messages: [row('good')], next: null });
    const hook = renderHook(({ active }) => useGroupHistory('A','group',active), { wrapper, initialProps: { active: true } });
    await waitFor(() => expect(hook.result.current.messages).toHaveLength(1));
    let signal: AbortSignal | undefined;
    mocks.fetch.mockImplementationOnce((_owner, _group, _cursor, pendingSignal) => {
      signal = pendingSignal; return new Promise(() => {});
    });
    act(() => { void hook.result.current.refetch(); });
    await waitFor(() => expect(signal).toBeDefined());
    hook.rerender({ active: false });
    await waitFor(() => expect(signal?.aborted).toBe(true));
    expect(hook.result.current.visible).toBe(false);
    expect(hook.result.current.messages.map(r => r.id)).toEqual(['good']);
  });
  it("does not mix late outgoing-account data into the next account", async () => {
    let finish!: (page: MessagePage) => void;
    let signal: AbortSignal | undefined;
    mocks.fetch.mockImplementationOnce((_owner, _group, _cursor, pendingSignal) => {
      signal = pendingSignal; return new Promise<MessagePage>(resolve => { finish = resolve; });
    }).mockResolvedValueOnce({ messages: [{ ...row('B'), from_user_id: 'B' }], next: null });
    const { wrapper } = context();
    const hook = renderHook(({ owner }) => useGroupHistory(owner,'group'), { wrapper, initialProps: { owner: 'A' } });
    await waitFor(() => expect(signal).toBeDefined());
    hook.rerender({ owner: 'B' });
    await waitFor(() => expect(hook.result.current.messages[0]?.from_user_id).toBe('B'));
    expect(signal?.aborted).toBe(true);
    await act(async () => { finish({ messages: [row('A')], next: null }); });
    expect(hook.result.current.messages.map(r => r.id)).toEqual(['B']);
  });
  it("recovers from the Strict Mode cleanup cycle", async () => {
    mocks.fetch.mockImplementation(async (_owner, _group, _cursor, signal: AbortSignal) => {
      if (signal.aborted) throw new Error('cancelled');
      return { messages: [row('one')], next: null };
    });
    const { wrapper } = context(true);
    const hook = renderHook(() => useGroupHistory('A','group'), { wrapper });
    await waitFor(() => expect(hook.result.current.isSuccess).toBe(true));
    expect(hook.result.current.messages.map(r => r.id)).toEqual(['one']);
  });
});
