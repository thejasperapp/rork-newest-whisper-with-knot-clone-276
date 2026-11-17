import { StrictMode, type ReactNode } from "react";
import { act, cleanup, renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { GroupSummary, GroupSummaryPage } from "@/lib/groupSummaries";
const mocks = vi.hoisted(() => ({ fetch: vi.fn() }));
vi.mock("@/lib/groupSummaries", async importOriginal => ({ ...await importOriginal<typeof import("@/lib/groupSummaries")>(), fetchGroupSummaries: mocks.fetch }));
import { useGroupSummaries } from "./useGroupSummaries";
const row = (id: string) => ({ group_id: id, last_message_id: id } as GroupSummary);
const clients: QueryClient[] = [];
function context(strict = false) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } }); clients.push(client);
  const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{strict ? <StrictMode>{children}</StrictMode> : children}</QueryClientProvider>;
  return { client, wrapper };
}
afterEach(() => { cleanup(); clients.forEach(client => client.clear()); clients.length = 0; vi.resetAllMocks(); });
describe("group summary query ownership", () => {
  it("pages independently of direct messages and refreshes the loaded range atomically", async () => {
    const cursor = { id: 'cursor', createdAt: '2026-11-07T12:00:00.123456Z' };
    mocks.fetch.mockResolvedValueOnce({ groups: [row('busy')], next: cursor }).mockResolvedValueOnce({ groups: [row('quiet')], next: null });
    const { wrapper } = context();
    const hook = renderHook(() => useGroupSummaries('A'), { wrapper });
    await waitFor(() => expect(hook.result.current.groups).toHaveLength(1));
    await act(async () => { await hook.result.current.fetchNextPage(); });
    await waitFor(() => expect(hook.result.current.groups.map(r => r.group_id)).toEqual(['busy','quiet']));
    expect(mocks.fetch.mock.calls[1][1]).toEqual(cursor);
    let finish!: (page: GroupSummaryPage) => void;
    mocks.fetch.mockResolvedValueOnce({ groups: [row('new')], next: cursor }).mockImplementationOnce(() => new Promise<GroupSummaryPage>(resolve => { finish = resolve; }));
    act(() => { void hook.result.current.refetch(); });
    await waitFor(() => expect(finish).toBeDefined());
    expect(hook.result.current.groups.map(r => r.group_id)).toEqual(['busy','quiet']);
    await act(async () => { finish({ groups: [row('busy'), row('quiet')], next: null }); });
    await waitFor(() => expect(hook.result.current.groups.map(r => r.group_id)).toEqual(['new','busy','quiet']));
  });
  it("pauses hidden inbox work while preserving good content", async () => {
    mocks.fetch.mockResolvedValueOnce({ groups: [row('good')], next: null });
    const { wrapper } = context();
    const hook = renderHook(({ active }) => useGroupSummaries('A', active), { wrapper, initialProps: { active: true } });
    await waitFor(() => expect(hook.result.current.groups).toHaveLength(1));
    let signal: AbortSignal | undefined;
    mocks.fetch.mockImplementationOnce((_owner, _cursor, pendingSignal) => { signal = pendingSignal; return new Promise(() => {}); });
    act(() => { void hook.result.current.refetch(); });
    await waitFor(() => expect(signal).toBeDefined());
    hook.rerender({ active: false });
    await waitFor(() => expect(signal?.aborted).toBe(true));
    expect(hook.result.current.groups.map(r => r.group_id)).toEqual(['good']);
  });
  it("isolates late responses and survives Strict Mode cleanup", async () => {
    let finish!: (page: GroupSummaryPage) => void;
    let outgoing: AbortSignal | undefined;
    mocks.fetch.mockImplementationOnce((_owner, _cursor, signal) => { outgoing = signal; return new Promise<GroupSummaryPage>(resolve => { finish = resolve; }); })
      .mockResolvedValue({ groups: [row('B')], next: null });
    const { wrapper } = context(true);
    const hook = renderHook(({ owner }) => useGroupSummaries(owner), { wrapper, initialProps: { owner: 'A' } });
    await waitFor(() => expect(outgoing).toBeDefined());
    hook.rerender({ owner: 'B' });
    await waitFor(() => expect(hook.result.current.groups.map(r => r.group_id)).toEqual(['B']));
    expect(outgoing?.aborted).toBe(true);
    await act(async () => { finish({ groups: [row('A')], next: null }); });
    expect(hook.result.current.groups.map(r => r.group_id)).toEqual(['B']);
  });
});
