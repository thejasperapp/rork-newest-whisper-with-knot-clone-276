import { meetingUUID } from './jasper-meeting-rules';

/** Private metadata never forms part of a team card. Existing prospect rows remain canonical. */
export type RecruiterClient = {
  revision: number; email: string; phone: string; preferences: string; relationshipNotes: string;
  meetingIds: string[]; followUp: string; followUpDue: string; nextMeetingAt: string;
  stage: string; stageEnteredAt: string | null; stageHistory: { stage: string; at: string }[];
};
export type RecruiterTeamCard = { id: string; publisherId: string; name: string; role: string; stage: string; update: string; publishedAt: string; revision: number };
export const clientStages = ['discovered', 'contacted', 'interested', 'meeting', 'ready', 'passed'];
export function emptyRecruiterClient(stage = ''): RecruiterClient {
  return { revision: 0, email: '', phone: '', preferences: '', relationshipNotes: '', meetingIds: [], followUp: '', followUpDue: '', nextMeetingAt: '', stage, stageEnteredAt: null, stageHistory: [] };
}
export function selectedMeetingIDs(raw: unknown): string[] {
  if (!Array.isArray(raw) || !raw.length || raw.length > 8 || raw.some((id) => typeof id !== 'string' || !meetingUUID.test(id)) || new Set(raw).size !== raw.length) throw new Error('invalid_meeting_scope');
  return raw.map((id: string) => id.toLowerCase());
}
export function updateRecruiterClient(current: RecruiterClient, input: Record<string, unknown>): RecruiterClient {
  if (input.revision !== current.revision) throw new Error('revision_conflict');
  const next = structuredClone(current);
  for (const [key, maximum] of Object.entries({ email: 254, phone: 60, preferences: 1200, relationshipNotes: 4000, followUp: 600, followUpDue: 10, nextMeetingAt: 40 })) {
    const value = input[key];
    if (value === undefined) continue;
    if (typeof value !== 'string' || value.length > maximum) throw new Error('invalid_client');
    (next as unknown as Record<string, unknown>)[key] = value.trim();
  }
  if (next.email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(next.email)) throw new Error('invalid_client');
  if (next.followUpDue && (!/^\d{4}-\d{2}-\d{2}$/.test(next.followUpDue) || !Number.isFinite(Date.parse(next.followUpDue)))) throw new Error('invalid_client');
  if (next.nextMeetingAt && !Number.isFinite(Date.parse(next.nextMeetingAt))) throw new Error('invalid_client');
  if (input.meetingIds !== undefined) next.meetingIds = Array.isArray(input.meetingIds) && input.meetingIds.length === 0 ? [] : selectedMeetingIDs(input.meetingIds);
  next.revision++;
  return next;
}
/** Explicit allowlist; never spread a prospect, metadata, or AI answer into shared storage. */
export function reviewedTeamCard(input: Record<string, unknown>, publisherId: string, id: string, revision: number): RecruiterTeamCard {
  if (input.confirm !== true) throw new Error('confirmation_required');
  for (const [key, maximum] of Object.entries({ name: 160, role: 30, stage: 30, update: 1200 })) {
    if (typeof input[key] !== 'string' || (input[key] as string).length > maximum) throw new Error('invalid_client');
  }
  if (!(input.name as string).trim() || !['creator', 'coach', 'athlete', 'unspecified'].includes(input.role as string) || !clientStages.includes(input.stage as string)) throw new Error('invalid_client');
  return { id, publisherId, name: (input.name as string).trim(), role: input.role as string, stage: input.stage as string, update: (input.update as string).trim(), publishedAt: new Date().toISOString(), revision: revision + 1 };
}
