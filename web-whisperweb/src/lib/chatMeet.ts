import { z } from "zod";
import { supabaseAnonKey, supabaseUrl } from "@/lib/supabase";
import { groupThemeSession } from "@/lib/groupThemeSession";

export const chatMeetSnapshot = z.object({
  eventID: z.string().uuid(), meetingID: z.string().uuid(), title: z.string(),
  startTime: z.string(), endTime: z.string(), cancelled: z.boolean(), deliveryComplete: z.boolean(),
  invitees: z.array(z.object({ userID: z.string().uuid(), username: z.string(), status: z.enum(["going", "declined"]).nullable() })).min(2).max(20),
});
export type ChatMeetInvitation = z.infer<typeof chatMeetSnapshot>;

export interface ChatMeetScheduleRequest {
  operation_id: string;
  conversation_kind: "direct" | "dating" | "group";
  peer_id?: string;
  group_id?: string;
  title: string;
  starts_at: string;
  ends_at: string;
  timezone: string;
}

/** Same protected, idempotent request as iOS. Server owns eligibility and card delivery. */
export async function scheduleChatMeet(accountID: string, request: ChatMeetScheduleRequest, signal: AbortSignal, retryEventID?: string): Promise<ChatMeetInvitation> {
  const uuid = z.string().uuid();
  if (!uuid.safeParse(request.operation_id).success || (request.conversation_kind === "group"
    ? request.peer_id !== undefined || !uuid.safeParse(request.group_id).success
    : !["direct", "dating"].includes(request.conversation_kind) || request.group_id !== undefined || !uuid.safeParse(request.peer_id).success)
    || (retryEventID !== undefined && !uuid.safeParse(retryEventID).success)) throw new Error("Reopen this conversation before scheduling a meeting.");
  if (signal.aborted) throw new Error("Meeting request interrupted. Check Meet before creating another.");
  const session = await groupThemeSession(accountID);
  const controller = new AbortController();
  const abort = (): void => controller.abort();
  const timer = window.setTimeout(abort, 30_000);
  session.signal.addEventListener("abort", abort); signal.addEventListener("abort", abort);
  try {
    if (signal.aborted || session.signal.aborted) throw new Error("Meeting request interrupted. Check Meet before creating another.");
    const response = await fetch(`${supabaseUrl}/rest/v1/rpc/whisper_chat_meet_${retryEventID ? "retry" : "schedule"}`, {
      method: "POST", signal: controller.signal, cache: "no-store", redirect: "error",
      headers: { "Content-Type": "application/json", apikey: supabaseAnonKey, Authorization: `Bearer ${session.token}` },
      body: JSON.stringify(retryEventID ? { event_id: retryEventID } : request),
    });
    session.check();
    if (!response.ok) {
      const failure = await response.json().catch(() => null) as { code?: string; message?: string } | null;
      if (failure?.code === "55000" && failure.message === "chat_meet_activation_pending") throw new Error("Meet invitations are not yet activated. Keep this request and check again later.");
      if (failure?.code === "42501") throw new Error("Meet couldn’t authorize this invitation. Direct chats need the recipient’s Meet permission; dating and groups must meet current eligibility and contact rules.");
      throw new Error("The meeting could not be confirmed. Keep this request to retry; check Meet before creating another.");
    }
    const raw: unknown = await response.json(); session.check();
    if (controller.signal.aborted) throw new Error("Meeting request interrupted. Keep this form to retry the same meeting.");
    if (retryEventID) {
      const latest = await chatMeet(accountID, retryEventID, undefined, signal);
      session.check();
      if (signal.aborted) throw new Error("Meeting check interrupted. Keep this form and check again.");
      return latest;
    }
    const result = chatMeetSnapshot.safeParse(raw);
    if (!result.success || !result.data.invitees.some(person => person.userID.toLowerCase() === accountID.toLowerCase()) || new Set(result.data.invitees.map(person => person.userID.toLowerCase())).size !== result.data.invitees.length) throw new Error("Couldn’t verify Meet’s response. Keep this request and check again.");
    return result.data;
  } finally { clearTimeout(timer); session.dispose(); session.signal.removeEventListener("abort", abort); signal.removeEventListener("abort", abort); }
}

/** Protected Meet RPC only. No legacy calendar fallback or mutation replay. */
export async function chatMeet(accountID: string, eventID: string, response?: "going" | "declined", signal?: AbortSignal): Promise<ChatMeetInvitation> {
  if (!z.string().uuid().safeParse(eventID).success) throw new Error("This invitation isn't available.");
  const session = await groupThemeSession(accountID);
  const controller = new AbortController();
  const abort = (): void => controller.abort();
  const timeout = window.setTimeout(abort, 30_000);
  session.signal.addEventListener("abort", abort);
  signal?.addEventListener("abort", abort);
  try {
    if (signal?.aborted || session.signal.aborted) throw new Error("Meeting check cancelled.");
    const result = await fetch(`${supabaseUrl}/rest/v1/rpc/whisper_chat_meet_${response ? "respond" : "get"}`, {
      method: "POST", signal: controller.signal, cache: "no-store", redirect: "error",
      headers: { "Content-Type": "application/json", apikey: supabaseAnonKey, Authorization: `Bearer ${session.token}` },
      body: JSON.stringify({ event_id: eventID, ...(response ? { response_status: response } : {}) }),
    });
    session.check();
    if (!result.ok) throw new Error("This invitation is unavailable or access changed. Check again before continuing.");
    const value = chatMeetSnapshot.safeParse(await result.json());
    session.check();
    if (!value.success || value.data.eventID.toLowerCase() !== eventID.toLowerCase()
      || !value.data.invitees.some(p => p.userID.toLowerCase() === accountID.toLowerCase())
      || new Set(value.data.invitees.map(p => p.userID.toLowerCase())).size !== value.data.invitees.length) throw new Error("Couldn't verify the meeting response.");
    return value.data;
  } finally {
    clearTimeout(timeout); session.dispose(); session.signal.removeEventListener("abort", abort); signal?.removeEventListener("abort", abort);
  }
}
