import { normalizedKnotReaction } from './knot-message-skills';

// Review-only metadata, never an approval or a background write.
export function validResponsibilityDraft(value: unknown, now = Date.now()): boolean {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const r = value as Record<string, unknown>;
  const keys = ['kind', 'title', 'instruction', 'searchQuery', 'minIntervalMinutes', 'maxIntervalMinutes', 'timezone', 'quietStart', 'quietEnd', 'endsAtISO'];
  if (Object.keys(r).length !== keys.length || Object.keys(r).some(key => !keys.includes(key)) ||
      !['public_tracking', 'goal_followup', 'creator_performance'].includes(String(r.kind)) ||
      typeof r.title !== 'string' || !r.title.trim() || r.title.length > 120 ||
      typeof r.instruction !== 'string' || !r.instruction.trim() || r.instruction.length > 3000 ||
      typeof r.searchQuery !== 'string' || r.searchQuery.length > 1000 ||
      (r.kind === 'public_tracking' ? !r.searchQuery.trim() : r.searchQuery !== '') ||
      typeof r.minIntervalMinutes !== 'number' || ![60, 180, 360, 1440].includes(r.minIntervalMinutes) ||
      typeof r.maxIntervalMinutes !== 'number' || !Number.isInteger(r.maxIntervalMinutes) || r.maxIntervalMinutes < r.minIntervalMinutes || r.maxIntervalMinutes > 10080 ||
      typeof r.timezone !== 'string' || r.timezone.length > 80 ||
      typeof r.quietStart !== 'number' || !Number.isInteger(r.quietStart) || r.quietStart < 0 || r.quietStart > 23 ||
      typeof r.quietEnd !== 'number' || !Number.isInteger(r.quietEnd) || r.quietEnd < 0 || r.quietEnd > 23 ||
      typeof r.endsAtISO !== 'string' || r.endsAtISO.length > 50 || !/(?:Z|[+-]\d{2}:\d{2})$/.test(r.endsAtISO)) return false;
  const end = Date.parse(r.endsAtISO);
  if (!Number.isFinite(end) || end <= now + 60000 || end > now + 30 * 86400000) return false;
  try { new Intl.DateTimeFormat('en-US', { timeZone: r.timezone }).format(now); } catch { return false; }
  return true;
}

export function reviewedMessageMetadata(metadata: string, allowReaction = false): string {
  const match = /^\s*```message\s*\n?([\s\S]*?)```\s*$/.exec(metadata);
  if (!match || metadata.length > 16000) return '';
  try {
    const raw = JSON.parse(match[1]) as Record<string, unknown>;
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return '';
    delete raw.shellProposal; delete raw.shellResult; delete raw.shellApproval;
    const reaction = allowReaction ? normalizedKnotReaction(raw.reaction) : undefined;
    if (reaction) raw.reaction = reaction; else delete raw.reaction;
    // Never forward model-selected account/thread IDs or grant state through
    // responsibility data. Existing native action approvals are unchanged.
    if ('responsibility' in raw && !validResponsibilityDraft(raw.responsibility)) {
      delete raw.responsibility; raw.responsibilityError = 'invalid_draft';
    }
    return '```message\n' + JSON.stringify(raw) + '\n```';
  } catch { return ''; }
}
