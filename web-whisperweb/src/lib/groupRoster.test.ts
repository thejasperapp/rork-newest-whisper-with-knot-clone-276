import { afterEach, describe, expect, it, vi } from "vitest";
import { changeGroupRoster, freshGroupForSend } from "./groupRoster";
const session = vi.hoisted(() => ({ check: vi.fn(), dispose: vi.fn() }));
vi.mock("./groupThemeSession", () => ({ groupThemeSession: async () => ({ ...session, token: "fixture", signal: new AbortController().signal }) }));
vi.mock("./supabase", () => ({ supabaseUrl: "https://fixture.test", supabaseAnonKey: "fixture" }));
const owner = "11111111-1111-4111-8111-111111111111", a = "22222222-2222-4222-8222-222222222222", b = "33333333-3333-4333-8333-333333333333", id = "44444444-4444-4444-8444-444444444444";
const row = { id, owner_id: owner, name: "Fixture", member_ids: [a], member_usernames: ["Alice"], business_id: null, created_at: null };
afterEach(() => { vi.unstubAllGlobals(); vi.clearAllMocks(); });
describe("group roster changes", () => {
  it("new sends fail closed for removed membership, missing legacy registry and unavailable reads", async () => {
    for (const value of [[], [{...row,owner_id:b,member_ids:[b]}]]) {
      vi.stubGlobal("fetch",vi.fn().mockResolvedValue(Response.json(value)));
      await expect(freshGroupForSend(id,a)).rejects.toThrow(/no longer available/);
    }
    vi.stubGlobal("fetch",vi.fn().mockResolvedValue(Response.json({}, {status:503})));
    await expect(freshGroupForSend(id,a)).rejects.toThrow(/verify/);
  });
  it("new sends use the latest confirmed roster", async () => {
    vi.stubGlobal("fetch",vi.fn().mockResolvedValue(Response.json([{...row,member_ids:[a,b],member_usernames:["Alice","Bob"]}])));
    expect((await freshGroupForSend(id,a)).member_ids).toEqual([a,b]);
  });
  it("reads the latest roster then uses owner and both old arrays as CAS filters, deduplicating additions", async () => {
    const fetcher = vi.fn().mockResolvedValueOnce(Response.json([row])).mockResolvedValueOnce(Response.json([{ ...row, member_ids: [a,b], member_usernames: ["Alice","Bob"] }])); vi.stubGlobal("fetch", fetcher);
    const next = await changeGroupRoster(id, owner, { add: [{id: b, username:"Bob"},{id:b,username:"Bob"},{id:owner,username:"Owner"}] });
    expect(next.member_ids).toEqual([a,b]);
    const url = new URL(fetcher.mock.calls[1][0]);
    expect(url.searchParams.get("owner_id")).toBe(`eq.${owner}`);
    expect(url.searchParams.get("member_ids")).toBe(`eq.{"${a}"}`);
    expect(url.searchParams.get("member_usernames")).toBe('eq.{"Alice"}');
    expect(fetcher.mock.calls[1][1].redirect).toBe("error");
  });
  it("does not claim success or replay when a concurrent roster update wins", async () => {
    const fetcher = vi.fn().mockResolvedValueOnce(Response.json([row])).mockResolvedValueOnce(Response.json([])); vi.stubGlobal("fetch", fetcher);
    await expect(changeGroupRoster(id, owner, { remove: a })).rejects.toThrow(/changed elsewhere/);
    expect(fetcher).toHaveBeenCalledTimes(2); expect(session.dispose).toHaveBeenCalled();
  });
  it("rejects non-owner without sending a mutation", async () => {
    const fetcher = vi.fn().mockResolvedValue(Response.json([row])); vi.stubGlobal("fetch", fetcher);
    await expect(changeGroupRoster(id, a, { add: [{id:b,username:"Bob"}] })).rejects.toThrow(/owner/);
    expect(fetcher).toHaveBeenCalledTimes(1);
  });
  it("does not re-add or repeat a mutation on replay after a lost response", async () => {
    const fetcher = vi.fn().mockResolvedValue(Response.json([row])); vi.stubGlobal("fetch", fetcher);
    expect((await changeGroupRoster(id, owner, {add:[{id:a,username:"Alice"}]})).member_ids).toEqual([a]);
    expect(fetcher).toHaveBeenCalledTimes(1);
  });
});
