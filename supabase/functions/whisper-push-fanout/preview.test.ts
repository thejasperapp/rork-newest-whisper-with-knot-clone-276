import { describe, expect, test } from "bun:test";
import { groupEnvelope, safePreview } from "./preview";

describe("APNs safe previews", () => {
  test("unwraps group identity before formatting shared cards", () => {
    const wire = '::wg-v1::85e52de7-890e-46fd-bb06-1a4fcdb4fa48::Friends::::whisper-post-v1::{"caption":"escaped } secret"}';
    expect(groupEnvelope(wire)?.name).toBe("Friends");
    expect(safePreview(wire)).toBe("Shared a post");
  });
  test("malformed payloads cannot expose JSON", () => {
    for (const wire of ['::wg-v1::invalid::name::{secret}', 'caption ::whisper-future-v8::{"x":"}secret"}', '{"raw":true}', '[1,2]']) {
      expect(safePreview(wire)).toBe("New message");
    }
  });
  test("bounds text and rejects nested envelopes", () => {
    expect(safePreview("a".repeat(200)).length).toBe(180);
    expect(safePreview("a".repeat(300000))).toBe("New message");
    expect(safePreview("::wg-v1::85e52de7-890e-46fd-bb06-1a4fcdb4fa48::Name::::wg-v1::bad")).toBe("New message");
    expect(safePreview("Meet at six\nby the cafe")).toBe("Meet at six by the cafe");
  });
});
