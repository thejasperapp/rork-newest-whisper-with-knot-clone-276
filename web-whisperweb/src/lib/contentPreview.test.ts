import { describe, expect, it } from "vitest";
import { contentPreview } from "./contentPreview";
import { orderInbox } from "./inboxOrdering";
import { decodeStoryMetadata, encodeStoryMetadata, type StorySticker } from "./storyStickers";

describe("human-readable Activity previews", () => {
  for (const kind of ["postmeta", "workout", "sharedpost", "film", "article", "recipe", "chart", "checkin", "macros", "healthshare", "profileshare", "story", "storytag", "teams", "calendar", "map", "grocery", "coach-proposal", "coach-macros", "coach-diet-plan", "thought-reply", "factcheck", "callsummary", "workoutproposal", "future-style"]) {
    it(`removes ${kind} envelopes but keeps authored text`, () => {
      const raw = `Before\n::whisper-${kind}-v1::${JSON.stringify({ private: 'payload } with "quotes"', nested: { values: [1, 2] } }, null, 2)}\nAfter`;
      expect(contentPreview(raw)).toBe("Before After");
      expect(contentPreview(`::whisper-${kind}-v1::{broken\nsecret`)).not.toMatch(/secret|broken|whisper|\{/);
    });
  }
  it("handles stacked envelopes, incomplete markers, stickers, and empty values", () => {
    expect(contentPreview('::whisper-postmeta-v1::{}\n::whisper-workout-v1::{}\nMorning session')).toBe("Morning session");
    expect(contentPreview("Nice ::whisper-broken")).toBe("Nice");
    expect(contentPreview("jasper-sticker://hi")).toBe("Sticker");
    expect(contentPreview(null)).toBe("");
  });
  it("preserves ordinary authored JSON and bounds output", () => {
    expect(contentPreview('{"example":true}')).toBe('{"example":true}');
    expect(contentPreview("a".repeat(100000)).length).toBe(160);
  });
});

describe("one chronological inbox", () => {
  const rows = [{ id: "dm", date: "2026-10-01", unread: 0 }, { id: "group", date: "2026-09-30", unread: 2 }, { id: "dating", date: "2026-09-29", unread: 1 }];
  it("interleaves all kinds with recent, oldest and unread sorting", () => {
    expect(orderInbox(rows, "recent").map(r => r.id)).toEqual(["dm", "group", "dating"]);
    expect(orderInbox(rows, "oldest").map(r => r.id)).toEqual(["dating", "group", "dm"]);
    expect(orderInbox(rows, "unread").map(r => r.id)).toEqual(["group", "dating", "dm"]);
    expect(rows[0].id).toBe("dm");
  });
});

it("round-trips native reference width without changing legacy metadata", () => {
  const sticker: StorySticker = { id: "fixture", kind: "text", x: .5, y: .5, scale: 1, rotation: 0, text: "Hello" };
  expect(decodeStoryMetadata(encodeStoryMetadata([sticker], 390))).toEqual({ stickers: [sticker], referenceStageWidth: 390 });
  expect(decodeStoryMetadata(encodeStoryMetadata([sticker]))).toEqual({ stickers: [sticker] });
  expect(decodeStoryMetadata('{"stickers":[],"referenceStageWidth":0}').referenceStageWidth).toBeUndefined();
});
