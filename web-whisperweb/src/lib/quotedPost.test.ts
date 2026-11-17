import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { loadQuotedPost } from "./quotedPost";

const mocks = vi.hoisted(() => ({ check: vi.fn(), dispose: vi.fn(), session: vi.fn() }));
vi.mock("@/lib/supabase", () => ({ supabaseAnonKey: "public-test-key", supabaseUrl: "https://example.test" }));
vi.mock("@/lib/groupThemeSession", () => ({ groupThemeSession: mocks.session }));
const postID = "12345678-1234-1234-1234-123456789012";
const original = { id: postID, user_id: "author", caption: "Fresh original", media_urls: ["https://example.test/photo.jpg"] };
let responses: unknown[][];
let request: ReturnType<typeof vi.fn>;
beforeEach(() => {
  vi.clearAllMocks();
  mocks.check.mockImplementation(() => {});
  mocks.session.mockResolvedValue({ token: "captured-account-token", signal: new AbortController().signal, check: mocks.check, dispose: mocks.dispose });
  responses = [[original], [{ user_id: "author", is_private: false }], [], []];
  request = vi.fn(async () => new Response(JSON.stringify(responses.shift() ?? []), { status: 200 }));
  vi.stubGlobal("fetch", request);
});
afterEach(() => vi.unstubAllGlobals());
describe("quoted original visibility", () => {
  it("hydrates current media with captured credentials", async () => {
    const result = await loadQuotedPost(postID, "viewer", new AbortController().signal);
    expect(result?.post.caption).toBe("Fresh original");
    expect(result?.post.media_urls).toEqual(original.media_urls);
    expect(request.mock.calls[0]?.[1].headers.Authorization).toBe("Bearer captured-account-token");
    expect(mocks.dispose).toHaveBeenCalledOnce();
  });
  it("does not fall back to a deleted post snapshot", async () => {
    responses = [[]];
    expect(await loadQuotedPost(postID, "viewer", new AbortController().signal)).toBeNull();
  });
  it("fails closed for an unknown author", async () => {
    responses = [[original], []];
    expect(await loadQuotedPost(postID, "viewer", new AbortController().signal)).toBeNull();
  });
  it("hides blocked originals", async () => {
    responses[2] = [{ blocked_user_id: "author" }];
    expect(await loadQuotedPost(postID, "viewer", new AbortController().signal)).toBeNull();
  });
  it("hides private originals without an accepted follow", async () => {
    responses[1] = [{ user_id: "author", is_private: true }];
    expect(await loadQuotedPost(postID, "viewer", new AbortController().signal)).toBeNull();
  });
  it("permits a followed private original", async () => {
    responses = [[original], [{ user_id: "author", is_private: true }], [], [{ follower_id: "viewer" }], [{ post_id: postID }]];
    expect((await loadQuotedPost(postID, "viewer", new AbortController().signal))?.liked).toBe(true);
  });
  it("distinguishes failed reads from unavailable posts", async () => {
    request.mockResolvedValue(new Response("unavailable", { status: 503 }));
    await expect(loadQuotedPost(postID, "viewer", new AbortController().signal)).rejects.toThrow("Couldn't load");
    expect(mocks.dispose).toHaveBeenCalledOnce();
  });
  it("rejects stale account results and invalid IDs", async () => {
    mocks.check.mockImplementation(() => { throw new Error("Account changed"); });
    await expect(loadQuotedPost(postID, "viewer", new AbortController().signal)).rejects.toThrow("Account changed");
    expect(await loadQuotedPost("invalid", "viewer", new AbortController().signal)).toBeNull();
    expect(request).not.toHaveBeenCalled();
  });
});
