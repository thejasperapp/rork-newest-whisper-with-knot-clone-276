import { describe, expect, it, vi } from "vitest";
vi.mock("@/lib/supabase", () => ({ supabase: {}, MEDIA_BUCKET: "test", mediaPublicUrl: () => "" }));
vi.mock("@/lib/api", () => ({ sendMessage: vi.fn() }));
import { collectGroupMessages } from "@/lib/groupChats";
import { collapseMeetMessages, meetEventID } from "./meetMessageIdentity";
import type { WhisperMessage } from "./types";

const event = "10000000-0000-4000-8000-000000000001";
const group = "20000000-0000-4000-8000-000000000001";
const body = (id: string, eventID = event): string => `::whisper-calendar-v1::${JSON.stringify({ id, eventID, kind: "chat-meet", title: "Test" })}`;
const row = (id: string, recipient: string, time: string, message = body(id)): WhisperMessage => ({ id, from_user_id: "organizer", from_username: "Owner", to_user_id: recipient, to_username: recipient, body: message, created_at: time, read_at: null });

describe("Meet presentation identity", () => {
  it("collapses recipient-specific bodies across time buckets and retains real receipts", () => {
    const a = row("delivery-a", "alice", "2026-09-26T12:00:09Z");
    const b = { ...row("delivery-b", "bob", "2026-09-26T12:00:11Z"), read_at: "2026-09-26T12:01:00Z" };
    const wire = [a, b, b].map(r => ({ ...r, body: `::wg-v1::${group}::Friends::${r.body}` }));
    const messages = collectGroupMessages(wire, group);
    expect(messages).toHaveLength(1);
    expect(messages[0].deliveryIDs).toEqual(["delivery-a", "delivery-b"]);
    expect(messages[0].receipts).toEqual([{ userID: "bob", username: "bob", readAt: b.read_at }]);
  });
  it("keeps distinct meetings and groups separate", () => {
    const rows = [row("a", "alice", "2026-09-26T12:00:00Z"), row("b", "alice", "2026-09-26T12:00:00Z", body("b", "10000000-0000-4000-8000-000000000002"))].map(r => ({ ...r, body: `::wg-v1::${group}::Friends::${r.body}` }));
    expect(collectGroupMessages(rows, group)).toHaveLength(2);
    expect(collectGroupMessages(rows, "20000000-0000-4000-8000-000000000002")).toEqual([]);
  });
  it("collapses direct repeats without crossing directed threads", () => {
    const a = row("a", "alice", "2026-09-26T12:00:00Z");
    const b = row("b", "alice", "2026-09-26T13:00:00Z");
    expect(collapseMeetMessages([a, b])).toHaveLength(1);
    expect(collapseMeetMessages([a, { ...b, thread_id: "dating-thread" }])).toHaveLength(2);
    expect(collapseMeetMessages([a, { ...b, to_user_id: "bob" }])).toHaveLength(2);
  });
  it("does not collapse legacy updates, plain text, or malformed cards", () => {
    expect(meetEventID("::whisper-calendar-v1::{bad}")).toBeNull();
    expect(meetEventID(body("a").replace("chat-meet", "update"))).toBeNull();
    expect(collapseMeetMessages([row("a", "alice", "", "hello"), row("b", "alice", "", "hello")])).toHaveLength(2);
  });
});
