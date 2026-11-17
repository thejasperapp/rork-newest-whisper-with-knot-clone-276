import { describe, expect, it } from "vitest";
import { conversationKey, conversationThreadId } from "./conversationIdentity";
import { buildMatched, decodeMatchToken } from "./datingMatch";

describe("conversation identities", () => {
  const a = "00000000-0000-4000-8000-000000000001";
  const b = "00000000-0000-4000-8000-000000000002";
  it("keeps direct history stable and isolates dating on both sides", async () => {
    const direct = await conversationThreadId(a, b);
    const dating = await conversationThreadId(a, b, "dating");
    expect(direct).not.toBe(dating);
    expect(dating).toBe(await conversationThreadId(b.toUpperCase(), a.toUpperCase(), "dating"));
    expect(direct).toBe(await conversationThreadId(b, a, "direct"));
    expect(dating).toMatch(/^[a-f0-9-]{36}$/);
  });
  it("keeps selection, drafts and local deletion independent", () => {
    expect(conversationKey({ otherUserId: a })).toBe(a);
    expect(conversationKey({ otherUserId: a, kind: "direct" })).toBe(a);
    expect(conversationKey({ otherUserId: a, kind: "dating" })).toBe(`dating:${a}`);
  });
  it("requires a valid sender in match tokens", () => {
    expect(decodeMatchToken("::whisper-matched-v1::{bad")).toBeNull();
    expect(decodeMatchToken("::whisper-matched-v1::{}")).toBeNull();
    expect(decodeMatchToken(buildMatched(a, "Sample"))?.from).toBe(a);
  });
});
