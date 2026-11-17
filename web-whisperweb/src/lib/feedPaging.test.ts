import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Session } from "@supabase/supabase-js";
import { QueryClient } from "@tanstack/react-query";
import type { WhisperPost } from "./types";
const mocks = vi.hoisted(() => ({ fetch: vi.fn(), session: vi.fn() }));
vi.mock("./api", () => ({ fetchFeed: vi.fn(), fetchLikeCounts: vi.fn(async () => ({})), fetchCommentCounts: vi.fn(async () => ({})), fetchRepostCounts: vi.fn(async () => ({})) }));
vi.mock("./supabase", async () => {
  const { createClient } = await import("@supabase/supabase-js");
  const client = createClient("https://feed.invalid", "unit-test-key", {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }, global: { fetch: mocks.fetch },
  });
  vi.spyOn(client.auth, "getSession").mockImplementation(mocks.session);
  return { supabase: client };
});
import { fetchRankedFeedPage } from "./feedAlgorithm";
import { feedWindow, invalidateFeedSnapshot, removePagedFeedPost, uniqueFeedPosts, type FeedPage } from "./feedPaging";
const owner = "11111111-1111-4111-8111-111111111111";
const auth = (id: string) => ({ data: { session: { user: { id } } as Session }, error: null });
const post = (index: number) => ({ id: `aaaaaaaa-aaaa-4aaa-8aaa-${String(index).padStart(12,'0')}`, caption: "Hello", user_id: owner, is_reel: false, created_at: "2026-11-07T12:00:00.123456+00:00" } as WhisperPost);
const signals = { likeCounts: {}, commentCounts: {}, repostCounts: {}, followingIds: new Set<string>() };
beforeEach(() => {
  mocks.session.mockResolvedValue(auth(owner));
  mocks.fetch.mockImplementation(async () => new Response("[]", { headers: { "Content-Type": "application/json" } }));
});
afterEach(() => vi.clearAllMocks());
describe("feed continuation", () => {
  it("requests 24 plus sentinel with stable ordering and combined safety/continuation filters", async () => {
    const cursor = { id: post(24).id, createdAt: post(24).created_at };
    await fetchRankedFeedPage(owner, cursor);
    const url = new URL(String(mocks.fetch.mock.calls.find(call => String(call[0]).includes('/whisper_posts'))![0]));
    expect(url.searchParams.get('limit')).toBe('25');
    expect(url.searchParams.get('order')).toBe('created_at.desc.nullslast,id.desc');
    const filter = url.searchParams.get('or')!;
    expect(filter).toContain('is_reel.is.null,is_reel.eq.false,caption.ilike.*feed*:true*');
    expect(filter).toContain(`created_at.eq.${cursor.createdAt},id.lt.${cursor.id}`);
    expect(url.searchParams.getAll('or')).toHaveLength(1);
  });
  it("scopes community candidates on the server without interpolating IDs into OR filters", async () => {
    await fetchRankedFeedPage(owner, null, undefined, undefined, { kind: 'community', id: 'quiet,community' });
    const url = new URL(String(mocks.fetch.mock.calls.find(call => String(call[0]).includes('/whisper_posts'))![0]));
    expect(url.searchParams.get('community_id')).toBe('eq.quiet,community');
    expect(url.searchParams.get('or')).not.toContain('quiet,community');
    expect(url.searchParams.get('limit')).toBe('25');
  });
  it("escapes literal search punctuation and retains raw continuation with Waves", async () => {
    const cursor = { id: post(24).id, createdAt: post(24).created_at };
    await fetchRankedFeedPage(owner, cursor, undefined, undefined, { kind: 'search', term: 'fit%_*' });
    const url = new URL(String(mocks.fetch.mock.calls.find(call => String(call[0]).includes('/whisper_posts'))![0]));
    expect(url.searchParams.get('caption')).toBe('ilike.%fit\\%\\_\\*%');
    expect(url.searchParams.get('or')).not.toContain('is_reel');
    expect(url.searchParams.get('or')).toContain(`id.lt.${cursor.id}`);
    const rows = Array.from({ length: 25 }, (_, index) => ({ ...post(index), is_reel: true }));
    expect(feedWindow(rows, true).posts).toHaveLength(24);
    expect(feedWindow(rows, true).next?.id).toBe(rows[23].id);
  });
  it("takes the raw microsecond cursor before media/category filtering, never the ranked last row", () => {
    const rows = Array.from({ length: 25 }, (_, index) => ({ ...post(index), is_reel: true }));
    const window = feedWindow(rows);
    expect(window.posts).toEqual([]);
    expect(window.next).toEqual({ id: rows[23].id, createdAt: rows[23].created_at });
    expect(feedWindow(rows.slice(0,24)).next).toBeNull();
  });
  it("keeps earlier displayed edits on overlap and removes confirmed deletes only from paged shapes", () => {
    const first: FeedPage = { posts: [post(1), post(2)], next: null, signals };
    const second: FeedPage = { posts: [{ ...post(1), caption: 'older snapshot' }, post(3)], next: null, signals };
    expect(uniqueFeedPosts([first, second])).toEqual([post(1), post(2), post(3)]);
    const client = new QueryClient();
    client.setQueryData(['feed',owner,'pages'], { pages: [first, second], pageParams: [null, null] });
    client.setQueryData(['feed'], [post(1)]);
    removePagedFeedPost(client, post(1).id);
    expect(client.getQueryData<{ pages: FeedPage[] }>(['feed',owner,'pages'])?.pages.flatMap(p => p.posts).map(p => p.id)).toEqual([post(2).id, post(3).id]);
    expect(client.getQueryData(['feed'])).toEqual([post(1)]);
    client.clear();
  });
  it("rejects outgoing accounts, cancellations and mutation races without seeding signals", async () => {
    const callback = vi.fn();
    mocks.session.mockResolvedValue(auth('different-account'));
    await expect(fetchRankedFeedPage(owner, null, undefined, callback)).rejects.toThrow();
    expect(mocks.fetch).not.toHaveBeenCalled();
    mocks.session.mockResolvedValue(auth(owner));
    const controller = new AbortController(); controller.abort();
    await expect(fetchRankedFeedPage(owner, null, controller.signal, callback)).rejects.toThrow();
    mocks.fetch.mockImplementation(async (input: unknown) => {
      if (String(input).includes('/whisper_posts')) invalidateFeedSnapshot();
      return new Response('[]');
    });
    await expect(fetchRankedFeedPage(owner, null, undefined, callback)).rejects.toThrow();
    expect(callback).not.toHaveBeenCalled();
  });
  it("retains network failure as a retryable failure rather than a false empty feed", async () => {
    mocks.fetch.mockImplementation(async (input: unknown) => String(input).includes('/whisper_posts')
      ? new Response(JSON.stringify({ message: 'unavailable' }), { status: 503 }) : new Response('[]'));
    await expect(fetchRankedFeedPage(owner, null)).rejects.toThrow("Posts couldn't refresh");
  }, 15_000);
});
