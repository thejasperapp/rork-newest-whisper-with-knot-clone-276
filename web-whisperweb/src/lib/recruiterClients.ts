import { z } from 'zod';
import { jasperMeetingRequest } from './jasperMeetings';
import type { Prospect, RecruiterPromotion } from './recruiter';

export const clientSchema = z.object({ revision: z.number().int(), email: z.string().max(254).email().or(z.literal('')), phone: z.string().max(60), preferences: z.string().max(1200), relationshipNotes: z.string().max(4000), meetingIds: z.array(z.string().uuid()).max(8), followUp: z.string().max(600), followUpDue: z.string().max(10), nextMeetingAt: z.string().max(40), stage: z.string(), stageEnteredAt: z.string().nullable(), stageHistory: z.array(z.object({ stage: z.string(), at: z.string() })) });
export type RecruiterClient = z.infer<typeof clientSchema>;
export type ClientTeam = { id: string; name: string };
export type ClientTeamCard = { id: string; publisherId: string; name: string; role: string; stage: string; update: string; publishedAt: string; revision: number };
export type ClientView = 'all' | 'overdue' | 'stalled' | 'upcoming' | 'promoted';
export const clientViewLabels: Record<ClientView, string> = { all: 'All people', overdue: 'Overdue', stalled: 'Stalled', upcoming: 'Upcoming meetings', promoted: 'Recently promoted' };
export const clientStageLabels: Record<string, string> = { discovered: 'Sourced', contacted: 'Contacted', interested: 'In talks', meeting: 'Evaluating', ready: 'Offer', passed: 'Passed' };
export async function loadRecruiterClients(owner: string, signal?: AbortSignal): Promise<Record<string, RecruiterClient>> {
  const response = await jasperMeetingRequest<{ clients: unknown }>(owner, 'clients/list', undefined, signal);
  return z.record(clientSchema).parse(response.clients);
}
export async function loadRecruiterClient(owner: string, id: string, signal?: AbortSignal): Promise<RecruiterClient> {
  return clientSchema.parse(await jasperMeetingRequest(owner, `clients/profile?id=${id}`, undefined, signal));
}
export async function saveRecruiterClient(owner: string, id: string, client: RecruiterClient): Promise<RecruiterClient> {
  return clientSchema.parse(await jasperMeetingRequest(owner, `clients/profile?id=${id}`, clientSchema.parse(client)));
}
/** Recorded transitions only: ordinary note edits cannot reset this clock. */
export function stageAge(client: RecruiterClient | undefined, status: string, now = Date.now()): number | null {
  if (client?.stage !== status || !client.stageEnteredAt) return null;
  const time = Date.parse(client.stageEnteredAt);
  return Number.isFinite(time) ? Math.max(0, Math.floor((now - time) / 86400000)) : null;
}
export function clientMatches(view: ClientView, p: Prospect, client: RecruiterClient | undefined, promotions: RecruiterPromotion[], now = Date.now()): boolean {
  const today = new Date(now).toLocaleDateString('en-CA');
  if (view === 'all') return true;
  if (view === 'promoted') return promotions.some((r) => (r.promoted_id === p.prospect_user_id || (!!p.prospect_username && r.promoted_username.toLowerCase() === p.prospect_username.toLowerCase())) && Date.parse(r.created_at ?? '') >= now - 30 * 86400000);
  if (p.status === 'passed') return false;
  if (view === 'stalled') return (stageAge(client, p.status, now) ?? -1) >= 8;
  if (view === 'upcoming') return !!client?.nextMeetingAt && Date.parse(client.nextMeetingAt) >= now;
  const due = client?.followUp ? client.followUpDue : p.next_action_due;
  return !!due && due < today;
}
