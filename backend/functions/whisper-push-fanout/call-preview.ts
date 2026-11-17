import { safePreview } from "./preview.ts";

/** Ring claims are recipient-scoped: one group call must still ring every member. */
export function callPushKey(callID: string, recipient: string): string {
  return JSON.stringify([callID.toLowerCase(), recipient.toLowerCase()]);
}

/** Bounded, typed wire fields shared by alert and VoIP delivery. */
export function callMetadata(body: string, recipient: string): Record<string, string> {
  try {
    if (body.length > 65536) return {};
    const data = JSON.parse(body.slice("::whisper-call-v1::".length));
    if (!data || typeof data !== "object" || Array.isArray(data)) return {};
    const result: Record<string, string> = { recipient_user_id: recipient };
    if (typeof data.meetingId === "string" && data.meetingId.length <= 128) result.meeting_id = data.meetingId;
    if (typeof data.groupId === "string" && /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(data.groupId)) {
      result.group_id = data.groupId;
      result.group_name = typeof data.groupName === "string" ? safePreview(data.groupName) : "Group call";
    }
    if (typeof data.at === "number" && Number.isFinite(data.at)) result.at = String(data.at);
    return result;
  } catch { return {}; }
}
