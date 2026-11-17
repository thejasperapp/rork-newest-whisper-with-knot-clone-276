import { z } from "zod";
import { groupThemeSession } from "@/lib/groupThemeSession";
import { supabaseAnonKey, supabaseUrl } from "@/lib/supabase";

export const teamsPrefix = "::whisper-teams-v1::";
/** Only selects a resolver; matching text never verifies an invitation. */
export function teamsCardCandidate(body: string | null, messageId: string): boolean {
  return /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(messageId) && body === teamsPrefix + messageId.toLowerCase();
}
const cardSchema = z.object({
  messageId: z.string().uuid(), invitationId: z.string().uuid(), teamId: z.string().uuid(),
  inviterId: z.string().uuid(), recipientId: z.string().uuid(), version: z.string().regex(/^[1-9][0-9]{0,18}$/),
  teamName: z.string().min(1).max(120), status: z.enum(["pending", "accepted", "declined", "revoked", "expired"]),
  expiresAt: z.number().int().positive().safe(), occurredAt: z.number().int().positive().safe(), canOpen: z.boolean(),
}).strict();
export type TeamsCard = z.infer<typeof cardSchema>;
export interface TeamsMessageBinding { id: string; from_user_id: string; to_user_id: string | null }
/** Pins account and message participants and refuses redirects/cache. No membership writes. */
export async function loadTeamsCard(account: string, message: TeamsMessageBinding, signal?: AbortSignal): Promise<TeamsCard> {
  const session = await groupThemeSession(account);
  const abort = new AbortController();
  const cancel = (): void => abort.abort();
  const timeout = window.setTimeout(cancel, 15_000);
  session.signal.addEventListener("abort", cancel); signal?.addEventListener("abort", cancel);
  try {
    if (session.signal.aborted || signal?.aborted) throw new Error("Interrupted");
    const response = await fetch(`${supabaseUrl}/rest/v1/rpc/whisper_social_teams_card`, {
      method: "POST", redirect: "error", cache: "no-store", signal: abort.signal,
      headers: { "Content-Type": "application/json", apikey: supabaseAnonKey, Authorization: `Bearer ${session.token}` },
      body: JSON.stringify({ p_message_id: message.id }),
    });
    session.check();
    if (!response.ok) throw new Error("Invitation unavailable");
    const text = await response.text();
    if (text.length > 16_384) throw new Error("Invalid response");
    const result = cardSchema.parse(JSON.parse(text));
    session.check();
    if (abort.signal.aborted || result.messageId.toLowerCase() !== message.id.toLowerCase()
      || result.inviterId.toLowerCase() !== message.from_user_id.toLowerCase()
      || result.recipientId.toLowerCase() !== message.to_user_id?.toLowerCase()
      || ![result.inviterId, result.recipientId].some(id => id.toLowerCase() === account.toLowerCase())
      || (result.canOpen && (result.status !== "pending" || result.recipientId.toLowerCase() !== account.toLowerCase()))) throw new Error("Invalid binding");
    return result;
  } finally {
    clearTimeout(timeout); session.signal.removeEventListener("abort", cancel); signal?.removeEventListener("abort", cancel); session.dispose();
  }
}
export const teamsStatusLabel: Record<TeamsCard["status"], string> = {
  pending: "Awaiting review in Teams", accepted: "Accepted in Teams", declined: "Declined in Teams", revoked: "Invitation revoked", expired: "Invitation expired",
};
