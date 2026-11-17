import { describe, expect, it } from "vitest";
import { decodeStoryMetadata, encodeStoryMetadata, sharedPostCardSize, type StorySticker } from "./storyStickers";

const post: StorySticker = { id: "post", kind: "post", x: 0.5, y: 0.52, scale: 1, rotation: 0,
  postID: "original", imageURL: "https://example.com/photo.jpg", cardWidthFraction: 0.88, mediaAspectRatio: 0.75, mediaCount: 2 };

describe("shared post Story geometry", () => {
  it("preserves the source ratio across phone and desktop stages", () => {
    for (const width of [320, 390, 440, 506]) {
      const size = sharedPostCardSize(post, width);
      expect(size.width / size.height).toBeCloseTo(0.75);
      expect(size.width).toBeLessThanOrEqual(width * 0.88);
      expect(size.height).toBeLessThanOrEqual(width * 16 / 9 * 0.72);
    }
  });
  it("keeps legacy sizes and rejects malformed geometry", () => {
    expect(sharedPostCardSize({ ...post, cardWidthFraction: undefined }, 440)).toEqual({ width: 250, height: 312 });
    expect(sharedPostCardSize({ ...post, mediaAspectRatio: 0 }, 440)).toEqual({ width: 250, height: 312 });
    expect(sharedPostCardSize(post, Number.NaN)).toEqual({ width: 250, height: 312 });
  });
  it("retains native optional geometry and original post links", () => {
    expect(decodeStoryMetadata(encodeStoryMetadata([post])).stickers).toEqual([post]);
  });
});
