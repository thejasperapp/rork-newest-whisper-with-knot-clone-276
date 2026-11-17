import { describe, expect, test } from "bun:test";
import { authenticWebhook, eventIdentity, preferenceAllows, storyResponseAction } from "./policy";

const id = "20000000-0000-4000-8000-000000000001";
const other = "10000000-0000-4000-8000-000000000001";

describe("push admission policy", () => {
  test("requires the exact server credential", async () => {
    expect(await authenticWebhook(null, "server-test-key")).toBe(false);
    expect(await authenticWebhook("Bearer anon-test-key", "server-test-key")).toBe(false);
    expect(await authenticWebhook("Bearer user-test-key", "server-test-key")).toBe(false);
    expect(await authenticWebhook("Bearer server-test-key extra", "server-test-key")).toBe(false);
    expect(await authenticWebhook("Bearer server-test-key", "server-test-key")).toBe(true);
    expect(await authenticWebhook("Bearer x", "")).toBe(false);
  });
  test("uses real composite follow and like columns", () => {
    expect(eventIdentity("whisper_follows", { follower_id: id, followee_id: other })).not.toBeNull();
    expect(eventIdentity("whisper_follows", { follower_user_id: id, followee_user_id: other })).toBeNull();
    expect(eventIdentity("whisper_post_likes", { post_id: id, user_id: other })).not.toBeNull();
    expect(eventIdentity("toString", {})).toBeNull();
    expect(eventIdentity("whisper_messages", { id: "invalid" })).toBeNull();
  });
  test("normalizes timestamps but distinguishes a refollow", () => {
    const row = { follower_id: id, followee_id: other, created_at: "2026-09-23T12:00:00+00:00" };
    expect(eventIdentity("whisper_follows", row)).toBe(eventIdentity("whisper_follows", { ...row, created_at: "2026-09-23T12:00:00.000Z" }));
    expect(eventIdentity("whisper_follows", row)).not.toBe(eventIdentity("whisper_follows", { ...row, created_at: "2026-09-23T13:00:00Z" }));
  });
  test("master and quiet override individual categories", () => {
    expect(preferenceAllows(null, "WHISPER_DM")).toBe(true);
    expect(preferenceAllows({ master_enabled: false, dms: true }, "WHISPER_DM")).toBe(false);
    expect(preferenceAllows({ quiet_mode: true }, "WHISPER_CALL")).toBe(false);
    expect(preferenceAllows({ story_responses: false }, "WHISPER_STORY_RESPONSE")).toBe(false);
    expect(preferenceAllows({ missed_calls: false }, "WHISPER_CALL_MISSED")).toBe(false);
    expect(preferenceAllows({ likes: false }, "WHISPER_DM")).toBe(true);
  });
  test("likes and reactions never masquerade as question answers", () => {
    expect(storyResponseAction("like")).toBe("liked your story");
    expect(storyResponseAction("reaction")).toBe("reacted to your story");
    expect(storyResponseAction("future")).toBe("responded to your story");
  });
});
