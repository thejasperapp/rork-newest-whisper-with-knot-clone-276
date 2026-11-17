import { afterEach, describe, expect, it, vi } from "vitest";
import type { WhisperPost } from "./types";
const mocks = vi.hoisted(() => ({ feed: vi.fn(), likes: vi.fn(), comments: vi.fn(), reposts: vi.fn(), follows: vi.fn() }));
vi.mock("./api", () => ({ fetchFeed: mocks.feed, fetchLikeCounts: mocks.likes, fetchCommentCounts: mocks.comments, fetchRepostCounts: mocks.reposts }));
vi.mock("./supabase", () => ({ supabase: { from: () => ({ select: () => ({ eq: () => ({ limit: mocks.follows }) }) }) } }));
vi.mock("./dearAlgorithm", () => ({ algorithmKeywords: () => [] }));
import { fetchRankedFeed, rankFeed } from "./feedAlgorithm";
const post = (id: string, author = id): WhisperPost => ({ id, user_id: author, username: author, caption: "Hello", kind: null, symbol: null, accent_hex: null, media_count: 0, media_urls: [], is_ghost: false, is_reel: false, likes_count: 0, comments_count: 0, created_at: "2026-11-05T10:00:00Z" });
afterEach(() => { vi.useRealTimers(); vi.resetAllMocks(); });

describe("ranked feed signal handoff", () => {
  it("hands off the counts already used for ranking and only the rendered slice", async () => {
    vi.useFakeTimers(); vi.setSystemTime(new Date("2026-11-05T11:00:00Z"));
    const candidates = [post("a"), post("b"), post("c")];
    mocks.feed.mockResolvedValue(candidates);
    mocks.likes.mockResolvedValue({ a: 3, b: 10 }); mocks.comments.mockResolvedValue({ c: 20 }); mocks.reposts.mockResolvedValue({ b: 2 });
    mocks.follows.mockResolvedValue({ data: [{ followee_id: "a" }] });
    const received = vi.fn();
    const result = await fetchRankedFeed("owner", 2, received);
    expect(result).toEqual(rankFeed(candidates, { likeCounts: { a: 3, b: 10 }, commentCounts: { c: 20 }, repostCounts: { b: 2 }, followingIds: new Set(["a"]) }).slice(0, 2));
    expect(received).toHaveBeenCalledTimes(1);
    expect(received.mock.calls[0][0]).toEqual(result);
    expect(received.mock.calls[0][1].likeCounts).toEqual({ a: 3, b: 10 });
    expect(mocks.likes).toHaveBeenCalledTimes(1); expect(mocks.comments).toHaveBeenCalledTimes(1); expect(mocks.reposts).toHaveBeenCalledTimes(1);
  });

  it("enriches even a single post so the visible card needs no second batch", async () => {
    mocks.feed.mockResolvedValue([post("a")]); mocks.likes.mockResolvedValue({ a: 4 }); mocks.comments.mockResolvedValue({}); mocks.reposts.mockResolvedValue({});
    const received = vi.fn();
    expect(await fetchRankedFeed(null, 60, received)).toEqual([post("a")]);
    expect(received.mock.calls[0][1].likeCounts).toEqual({ a: 4 });
    expect(mocks.follows).not.toHaveBeenCalled();
  });

  it("keeps the recency fallback when optional engagement services fail", async () => {
    const candidates = [post("a"), post("b"), post("c")];
    mocks.feed.mockResolvedValue(candidates); mocks.likes.mockRejectedValue(new Error("offline")); mocks.comments.mockRejectedValue(new Error("offline")); mocks.reposts.mockRejectedValue(new Error("offline")); mocks.follows.mockRejectedValue(new Error("offline"));
    const result = await fetchRankedFeed("owner");
    expect(result.map(row => row.id)).toEqual(["a", "b", "c"]);
  });

  it("starts relationship loading alongside candidates, not after them", async () => {
    let finish!: (posts: WhisperPost[]) => void;
    mocks.feed.mockReturnValue(new Promise<WhisperPost[]>(resolve => { finish = resolve; }));
    mocks.follows.mockResolvedValue({ data: [] });
    const pending = fetchRankedFeed("owner");
    expect(mocks.follows).toHaveBeenCalledTimes(1);
    finish([]);
    expect(await pending).toEqual([]);
    expect(mocks.likes).not.toHaveBeenCalled();
  });
});
