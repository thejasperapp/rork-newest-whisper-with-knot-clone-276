import { describe, expect, test } from "bun:test";
import { callMetadata, callPushKey } from "./call-preview";

describe("group call push contract", () => {
  test("every group recipient has an independent idempotency claim", () => {
    expect(callPushKey("call", "member-a")).not.toBe(callPushKey("call", "member-b"));
    expect(callPushKey("CALL", "MEMBER-A")).toBe(callPushKey("call", "member-a"));
    expect(callPushKey("a:b", "c")).not.toBe(callPushKey("a", "b:c"));
  });
  test("metadata preserves room, group, recipient and age", () => {
    const payload = "::whisper-call-v1::" + JSON.stringify({ meetingId: "room", groupId: "85e52de7-890e-46fd-bb06-1a4fcdb4fa48", groupName: "Weekend", at: 123 });
    expect(callMetadata(payload, "member")).toEqual({ meeting_id: "room", group_id: "85e52de7-890e-46fd-bb06-1a4fcdb4fa48", group_name: "Weekend", at: "123", recipient_user_id: "member" });
  });
  test("malformed and unbounded fields do not leak into the call UI", () => {
    expect(callMetadata("::whisper-call-v1::{broken", "member")).toEqual({});
    expect(callMetadata("::whisper-call-v1::null", "member")).toEqual({});
    expect(callMetadata("::whisper-call-v1::" + JSON.stringify({ groupId: "not-a-group", groupName: { secret: true } }), "member")).toEqual({ recipient_user_id: "member" });
  });
});
