import { act, cleanup, renderHook } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { WhisperProfile } from "@/lib/types";
const mocks = vi.hoisted(() => ({ search: vi.fn() }));
vi.mock("@/lib/api", () => ({ searchProfiles: mocks.search }));
import { useProfileSearch } from "./useProfileSearch";

const person = { user_id: "peer", username: "alice" } as WhisperProfile;
const clients: QueryClient[] = [];
function context() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  clients.push(client);
  return { client, wrapper: ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider> };
}
async function advance(ms: number) { await act(async () => { await vi.advanceTimersByTimeAsync(ms); }); }
beforeEach(() => { vi.useFakeTimers(); mocks.search.mockResolvedValue([person]); });
afterEach(() => { cleanup(); clients.forEach(client => client.clear()); clients.length = 0; vi.useRealTimers(); vi.resetAllMocks(); });

describe("production profile search", () => {
  it("waits for typing to settle and requests only the final term", async () => {
    const { wrapper } = context();
    const hook = renderHook(({ input }) => useProfileSearch("owner", input), { wrapper, initialProps: { input: "a" } });
    await advance(150);
    hook.rerender({ input: "ali" });
    await advance(150);
    expect(mocks.search).not.toHaveBeenCalled();
    expect(hook.result.current.isSearching).toBe(true);
    await advance(101);
    await advance(1);
    expect(mocks.search).toHaveBeenCalledTimes(1);
    expect(mocks.search.mock.calls[0][0]).toBe("ali");
    expect(hook.result.current.data).toEqual([person]);
    expect(hook.result.current.isSearching).toBe(false);
  });

  it("aborts the previous request immediately, hides old results, and cancels when cleared", async () => {
    const signals: AbortSignal[] = [];
    mocks.search.mockImplementation((_term, signal: AbortSignal) => { signals.push(signal); return new Promise(() => {}); });
    const { wrapper } = context();
    const hook = renderHook(({ input }) => useProfileSearch("owner", input), { wrapper, initialProps: { input: "alice" } });
    await advance(251);
    expect(signals).toHaveLength(1);
    hook.rerender({ input: "bob" });
    expect(signals[0].aborted).toBe(true);
    expect(hook.result.current.data).toBeUndefined();
    await advance(251);
    expect(signals).toHaveLength(2);
    hook.rerender({ input: "" });
    expect(signals[1].aborted).toBe(true);
    expect(hook.result.current.isSearching).toBe(false);
    await advance(300);
    expect(signals).toHaveLength(2);
  });

  it("keeps account results separate and rejects a late outgoing response", async () => {
    let finish!: (rows: WhisperProfile[]) => void;
    let outgoing!: AbortSignal;
    mocks.search.mockImplementationOnce((_term, signal: AbortSignal) => {
      outgoing = signal;
      return new Promise<WhisperProfile[]>(resolve => { finish = resolve; });
    }).mockResolvedValueOnce([{ ...person, username: "visible-to-B" }]);
    const { wrapper } = context();
    const hook = renderHook(({ owner }) => useProfileSearch(owner, "alice"), { wrapper, initialProps: { owner: "A" } });
    await advance(251);
    hook.rerender({ owner: "B" });
    await advance(1);
    expect(outgoing.aborted).toBe(true);
    await act(async () => { finish([person]); });
    await advance(1);
    expect(hook.result.current.data?.[0].username).toBe("visible-to-B");
  });

  it("does not search hashtags or closed pickers and aborts on close", async () => {
    const { wrapper } = context();
    const hook = renderHook(({ input, open }) => useProfileSearch("owner", input, open), { wrapper, initialProps: { input: "#fitness", open: true } });
    await advance(300);
    expect(mocks.search).not.toHaveBeenCalled();
    hook.rerender({ input: "alice", open: false });
    await advance(300);
    expect(mocks.search).not.toHaveBeenCalled();
    let signal!: AbortSignal;
    mocks.search.mockImplementation((_term, pendingSignal) => { signal = pendingSignal; return new Promise(() => {}); });
    hook.rerender({ input: "alice", open: true });
    await advance(1);
    hook.rerender({ input: "alice", open: false });
    expect(signal.aborted).toBe(true);
    expect(hook.result.current.data).toBeUndefined();
  });

  it("reports failures instead of a misleading empty success, then recovers on retry", async () => {
    mocks.search.mockRejectedValueOnce(new Error("private server detail")).mockRejectedValueOnce(new Error("private server detail"));
    const { wrapper } = context();
    const hook = renderHook(() => useProfileSearch("owner", "alice"), { wrapper });
    await advance(251);
    await advance(1100);
    expect(hook.result.current.isError).toBe(true);
    expect(hook.result.current.isSearching).toBe(false);
    await act(async () => { await hook.result.current.refetch(); });
    await advance(1);
    expect(hook.result.current.isError).toBe(false);
    expect(hook.result.current.data).toEqual([person]);
  });
});
