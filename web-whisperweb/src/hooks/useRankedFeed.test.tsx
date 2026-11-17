import { act, cleanup, renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider, useQuery } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { WhisperPost } from "@/lib/types";
import type { FeedSignals } from "@/lib/feedAlgorithm";
const mocks = vi.hoisted(() => ({ rank: vi.fn() }));
vi.mock("@/lib/feedAlgorithm", () => ({ fetchRankedFeedPage: mocks.rank }));
import { useRankedFeed } from "./useRankedFeed";

const posts = [{ id: "b" }, { id: "a" }] as WhisperPost[];
const signals: FeedSignals = { likeCounts: { a: 5, b: 3 }, commentCounts: { a: 2 }, repostCounts: { b: 1 }, followingIds: new Set() };
const clients: QueryClient[] = [];
function context() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false, staleTime: 30_000 } } });
  clients.push(client);
  return { client, wrapper: ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider> };
}
afterEach(() => { cleanup(); clients.forEach(client => client.clear()); clients.length = 0; vi.resetAllMocks(); });

describe("ranked feed request reuse", () => {
  it("isolates Search/Discover/Community pages and cancels obsolete terms", async () => {
    const observed: AbortSignal[] = [];
    mocks.rank.mockImplementation((_owner, _cursor, signal) => { observed.push(signal); return new Promise(() => {}); });
    const { client, wrapper } = context();
    const hook = renderHook(({ term, active }) => useRankedFeed("A", { kind: "search", term }, active), { wrapper, initialProps: { term: "first", active: true } });
    await waitFor(() => expect(observed).toHaveLength(1));
    hook.rerender({ term: "second", active: false });
    await waitFor(() => expect(observed[0].aborted).toBe(true));
    expect(hook.result.current.data).toEqual([]);
    expect(mocks.rank).toHaveBeenCalledTimes(1);
    hook.rerender({ term: "second", active: true });
    await waitFor(() => expect(observed).toHaveLength(2));
    expect(mocks.rank.mock.calls[1][4]).toEqual({ kind: "search", term: "second" });
    expect(client.getQueryState(["feed", "A", "pages", "search:second"])).toBeDefined();
    expect(client.getQueryState(["feed", "A", "pages"])).toBeUndefined();
    hook.unmount();
    await waitFor(() => expect(observed[1].aborted).toBe(true));
  });
  it("primes the three engagement queries without another initial count download", async () => {
    mocks.rank.mockImplementation(async (_owner, _cursor, _signal, onSignals) => { onSignals(posts, signals); return { posts, signals, next: null }; });
    const { client, wrapper } = context();
    const feed = renderHook(() => useRankedFeed("A"), { wrapper });
    await waitFor(() => expect(feed.result.current.data).toEqual(posts));
    const fetchCounts = vi.fn().mockResolvedValue({});
    const counts = renderHook(() => useQuery({ queryKey: ["feed-like-counts", ["a", "b"]], queryFn: fetchCounts, staleTime: 30_000 }), { wrapper });
    expect(counts.result.current.data).toEqual(signals.likeCounts);
    expect(fetchCounts).not.toHaveBeenCalled();
    expect(client.getQueryData(["feed-comment-counts", ["a", "b"]])).toEqual(signals.commentCounts);
    expect(client.getQueryData(["repost-counts", ["a", "b"]])).toEqual(signals.repostCounts);
    // Existing post-mutation invalidation still performs an authoritative read.
    await act(async () => { await client.invalidateQueries({ queryKey: ["feed-like-counts"] }); });
    expect(fetchCounts).toHaveBeenCalledTimes(1);
  });

  it("does not replace a newer count query with ranking's earlier snapshot", async () => {
    mocks.rank.mockImplementation(async (_owner, _cursor, _signal, onSignals) => { onSignals(posts, signals); return { posts, signals, next: null }; });
    const { client, wrapper } = context();
    client.setQueryData(["feed-like-counts", ["a", "b"]], { a: 9 });
    const hook = renderHook(() => useRankedFeed("A"), { wrapper });
    await waitFor(() => expect(hook.result.current.data).toEqual(posts));
    expect(client.getQueryData(["feed-like-counts", ["a", "b"]])).toEqual({ a: 9 });
  });

  it("cannot repopulate cleared count caches from a cancelled outgoing account", async () => {
    let finish!: () => void;
    mocks.rank.mockImplementation((_owner, _cursor, _signal, onSignals) => new Promise(resolve => {
      finish = () => { onSignals(posts, signals); resolve({ posts, signals, next: null }); };
    }));
    const { client, wrapper } = context();
    renderHook(() => useRankedFeed("A"), { wrapper });
    await waitFor(() => expect(finish).toBeDefined());
    await act(async () => { await client.cancelQueries(); client.clear(); finish(); });
    expect(client.getQueryData(["feed-like-counts", ["a", "b"]])).toBeUndefined();
    expect(client.getQueryData(["feed-comment-counts", ["a", "b"]])).toBeUndefined();
    expect(client.getQueryData(["repost-counts", ["a", "b"]])).toBeUndefined();
  });

  it("appends older pages without moving displayed posts and reuses combined counts", async () => {
    const cursor = { id: "cursor", createdAt: "2026-11-07T12:00:00.123456Z" };
    mocks.rank.mockImplementationOnce(async (_owner, _cursor, _signal, onSignals) => {
      onSignals(posts, signals); return { posts, signals, next: cursor };
    }).mockImplementationOnce(async (_owner, _cursor, _signal, onSignals) => {
      const older = [{ id: "c" }, { id: "a", caption: "stale overlap" }] as WhisperPost[];
      const more = { ...signals, likeCounts: { c: 7 } };
      onSignals(older, more); return { posts: older, signals: more, next: null };
    });
    const { client, wrapper } = context();
    const hook = renderHook(() => useRankedFeed("A"), { wrapper });
    await waitFor(() => expect(hook.result.current.data).toEqual(posts));
    await act(async () => { await hook.result.current.fetchNextPage(); });
    await waitFor(() => expect(hook.result.current.data.map(post => post.id)).toEqual(["b", "a", "c"]));
    expect(hook.result.current.data[1]).toEqual(posts[1]);
    expect(mocks.rank.mock.calls[1][1]).toEqual(cursor);
    expect(client.getQueryData(["feed-like-counts", ["a", "b", "c"]])).toEqual({ a: 5, b: 3, c: 7 });
  });
});
