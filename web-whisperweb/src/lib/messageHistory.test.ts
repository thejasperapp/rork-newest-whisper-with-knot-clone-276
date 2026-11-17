import { describe, expect, it } from "vitest";
import { beforeMessage, messagePage, uniqueHistory, RECENT_MESSAGE_LIMIT, OLDER_MESSAGE_LIMIT } from "./messageHistory";
import type { WhisperMessage } from "./types";

const row = (index: number, created_at: string | null = "2026-11-05T00:00:00.123456Z"): WhisperMessage => ({
  id: `11111111-1111-4111-8111-${String(index).padStart(12, "0")}`,
  from_user_id: "owner", to_user_id: "peer", from_username: null, to_username: null,
  body: `message ${index}`, created_at, read_at: null,
});

describe("message history", () => {
  it("returns exactly 100 recent messages, excluding the continuation sentinel", () => {
    const rows = Array.from({ length: 101 }, (_, i) => row(101 - i));
    const page = messagePage(rows, RECENT_MESSAGE_LIMIT);
    expect(page.messages).toHaveLength(100);
    expect(page.messages[0].id).toBe(row(2).id);
    expect(page.messages[page.messages.length - 1]?.id).toBe(row(101).id);
    expect(page.next).toEqual({ createdAt: rows[99].created_at, id: rows[99].id });
    expect(rows[0].id).toBe(row(101).id);
  });

  it("loads 50 older messages and stops at an exact final page", () => {
    const rows = Array.from({ length: 50 }, (_, i) => row(50 - i));
    const page = messagePage(rows, OLDER_MESSAGE_LIMIT);
    expect(page.messages).toHaveLength(50);
    expect(page.next).toBeNull();
    expect(messagePage([], RECENT_MESSAGE_LIMIT)).toEqual({ messages: [], next: null });
  });

  it("uses the ID as a strict timestamp tie-break and handles legacy null times", () => {
    const cursor = { id: row(50).id, createdAt: row(50).created_at };
    expect(beforeMessage(cursor)).toBe(`created_at.lt.${cursor.createdAt},and(created_at.eq.${cursor.createdAt},id.lt.${cursor.id}),created_at.is.null`);
    expect(beforeMessage({ ...cursor, createdAt: null })).toBe(`and(created_at.is.null,id.lt.${cursor.id})`);
  });

  it("rejects malformed cursor IDs and filter-injection timestamps", () => {
    expect(() => beforeMessage({ id: "-".repeat(36), createdAt: null })).toThrow();
    expect(() => beforeMessage({ id: row(1).id, createdAt: "2026-11-05),id.gt.1" })).toThrow();
  });

  it("deduplicates overlap with the recent page authoritative for edits and read receipts", () => {
    const old = row(3);
    const updated = { ...old, body: "edited", read_at: "2026-11-05T01:00:00Z" };
    const merged = uniqueHistory([
      { messages: [updated, row(4)], next: null },
      { messages: [row(1), row(2), old], next: null },
    ]);
    expect(merged.map(message => message.id)).toEqual([1, 2, 3, 4].map(i => row(i).id));
    expect(merged[2]).toEqual(updated);
  });

  it("orders null timestamps, microseconds, and equivalent timezone offsets deterministically", () => {
    const early = row(9, "2026-11-05T00:00:00.123455Z");
    const late = row(1, "2026-11-05T00:00:00.123456Z");
    const equivalent = row(2, "2026-11-05T01:00:00.123456+01:00");
    const rows = uniqueHistory([{ messages: [equivalent, late, early, row(8, null)], next: null }]);
    expect(rows.map(message => message.id)).toEqual([8, 9, 1, 2].map(i => row(i).id));
  });
});
