import { describe, expect, it } from "vitest";
import { collectGroupMessages } from "./groupChats";
import type { WhisperMessage } from "./types";
const group = "11111111-1111-4111-8111-111111111111";
const row = (id: string, sender: string, recipient: string, at: string, read: string | null = null): WhisperMessage => ({
  id, from_user_id: sender, to_user_id: recipient, from_username: sender, to_username: recipient,
  body: `::wg-v1::${group.toUpperCase()}::Friends: work::Hello`, created_at: at, read_at: read, logical_group_message_id: group,
});
describe("group delivery collapse", () => {
  it("keeps independent senders separate even if logical IDs match", () => {
    const messages = collectGroupMessages([row('a','sender-a','me','2026-11-07T12:00:00Z'), row('b','sender-b','me','2026-11-07T12:00:00Z')], group);
    expect(messages).toHaveLength(2);
    expect(new Set(messages.map(message => message.key)).size).toBe(2);
    expect(messages.map(message => message.deliveryIDs)).toEqual([['a'],['b']]);
  });
  it("keeps earliest chronology and every delivery/receipt including former recipients", () => {
    const messages = collectGroupMessages([
      row('late','me','current','2026-11-07T12:00:05Z'),
      row('first','me','former','2026-11-07T12:00:00Z','2026-11-07T13:00:00Z'),
      row('first','me','former','2026-11-07T12:00:00Z','2026-11-07T13:00:00Z'),
    ], group);
    expect(messages).toHaveLength(1);
    expect(messages[0].createdAt).toBe('2026-11-07T12:00:00Z');
    expect(messages[0].deliveryIDs).toEqual(['first','late']);
    expect(messages[0].receipts).toEqual([{ userID: 'former', username: 'former', readAt: '2026-11-07T13:00:00Z' }]);
  });
});
