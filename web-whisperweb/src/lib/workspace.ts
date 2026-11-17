import type { WorkKind, WorkView, WorkSummary } from '../../../functions/workspace-rules';
import { jasperMeetingRequest } from './jasperMeetings';
export type { WorkKind, WorkView, WorkBoard, WorkSummary, WorkPerson, IntakeSettings } from '../../../functions/workspace-rules';
export type WorkScope = { space: string; team: boolean };
export const workNames: Record<WorkKind, string> = { decision: 'Decision rooms', delivery: 'Client deliveries', request: 'Intake & approvals' };
export const workDescriptions: Record<WorkKind, string> = { decision: 'Explore options. Hear objections. Record a decision and revisit its outcome.', delivery: 'Keep internal work separate. Publish a reviewed version for your client to accept.', request: 'One front door for requests, with a responsible owner and visible progress.' };
export const workStatus = (value: string): string => value.replace(/_/g, ' ');
export const workPath = (scope: WorkScope, suffix = ''): string => `workspace${suffix}?space=${encodeURIComponent(scope.space)}&team=${scope.team ? '1' : '0'}`;
export function workRequest<T>(owner: string, scope: WorkScope, suffix = '', body?: unknown, signal?: AbortSignal): Promise<T> { return jasperMeetingRequest<T>(owner, workPath(scope, suffix), body, signal); }
export function workLink(scope: WorkScope, id?: string): string { const url = new URL('/work', window.location.origin); url.searchParams.set('portal', 'workspace'); url.searchParams.set('space', scope.space); url.searchParams.set('team', scope.team ? '1' : '0'); if (id) url.searchParams.set('id', id); return url.toString(); }
export function workNeedsAttention(item: WorkSummary, today = new Date().toISOString().slice(0, 10)): boolean {
  if (item.status === 'decided') return !!item.reviewOn && item.reviewOn <= today;
  return !['archived', 'reviewed', 'completed', 'declined', 'accepted'].includes(item.status) && ((!!item.deadline && item.deadline <= today) || ['submitted', 'awaiting_approval', 'changes_requested', 'in_review'].includes(item.status));
}
export function workActions(item: WorkView): { id: string; label: string; needsText?: boolean }[] {
  if (item.status === 'archived') return [];
  const actions: { id: string; label: string; needsText?: boolean }[] = [];
  if (item.kind === 'decision') {
    if (item.canManage && item.status === 'draft') actions.push({ id: 'open', label: 'Open discussion' });
    if (item.canDecide && item.status === 'discussing') actions.push({ id: 'decide', label: 'Record decision', needsText: true });
    if (item.canDecide && item.status === 'decided') actions.push({ id: 'review', label: 'Record outcome review', needsText: true });
  }
  if (item.kind === 'request') {
    const next: Record<string, { id: string; label: string }> = { submitted: { id: 'triage', label: 'Accept for triage' }, triaged: { id: 'seek_approval', label: 'Request approval' }, approved: { id: 'start', label: 'Start work' }, in_progress: { id: 'complete', label: 'Mark complete' } };
    if (item.canManage && next[item.status]) actions.push(next[item.status]);
    if (item.canDecide && item.status === 'awaiting_approval') actions.push({ id: 'approve', label: 'Approve request', needsText: true }, { id: 'decline', label: 'Decline request', needsText: true });
  }
  return actions;
}
