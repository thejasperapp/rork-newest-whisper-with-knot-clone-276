import { meetingUUID } from './jasper-meeting-rules';

export type WorkKind = 'decision' | 'delivery' | 'request';
export type WorkPerson = { id: string; username: string };
export type WorkVersion = { number: number; title: string; summary: string; url: string; milestones: string; at: string; response?: { status: 'accepted' | 'changes_requested'; text: string; actor: string; at: string } };
export type WorkComment = { id: string; author: string; text: string; audience: 'internal' | 'shared'; at: string };
export type WorkEvent = { id: string; actor: string; action: string; at: string; detail?: string; contentRevision?: number };
export type WorkItem = {
  id: string; kind: WorkKind; title: string; brief: string; alternatives: string; deadline: string; reviewOn: string;
  assigneeId: string; createdBy: string; requesterId: string; status: string; outcome: string; internalNote: string;
  category: string; priority: string; revision: number; createdAt: string; updatedAt: string;
  client: WorkPerson | null; publishedVersion: number | null; versions: WorkVersion[]; comments: WorkComment[]; events: WorkEvent[];
};
export type WorkAccess = { member: boolean; owner: boolean; caller: string };
export type WorkView = WorkItem & { canManage: boolean; canDecide: boolean; canRespond: boolean; external: boolean };
export type WorkSummary = Pick<WorkView, 'id' | 'kind' | 'title' | 'status' | 'deadline' | 'reviewOn' | 'assigneeId' | 'revision' | 'updatedAt' | 'external'>;
export type IntakeSettings = { revision: number; people: WorkPerson[]; instructions: string; assigneeId: string; turnaroundDays: number };
export type WorkBoard = { items: WorkSummary[]; member: boolean; owner: boolean; canSubmit: boolean; intakeInstructions: string; checkedAt: string };

export function workText(value: unknown, maximum: number, required = false): string {
  if (typeof value !== 'string' || value.length > maximum || (required && !value.trim())) throw new Error('invalid_work');
  return value.trim();
}
export function workDate(value: unknown): string {
  const text = workText(value ?? '', 10);
  if (text && (!/^20\d{2}-\d{2}-\d{2}$/.test(text) || !Number.isFinite(Date.parse(`${text}T00:00:00Z`)) || new Date(`${text}T00:00:00Z`).toISOString().slice(0, 10) !== text)) throw new Error('invalid_work');
  return text;
}
export function workID(value: unknown): string { if (typeof value !== 'string' || !meetingUUID.test(value)) throw new Error('invalid_work'); return value.toLowerCase(); }
export function managesWork(item: WorkItem, access: WorkAccess): boolean { return access.member && (access.owner || item.createdBy === access.caller || item.assigneeId === access.caller); }
/** External delivery views are an allowlist, never a spread of the private item. */
export function workView(item: WorkItem, access: WorkAccess, canSubmit: boolean): WorkView | null {
  const common = { canManage: managesWork(item, access), canDecide: access.member && item.assigneeId === access.caller, canRespond: false, external: !access.member };
  if (access.member) return { ...item, ...common, canRespond: item.kind === 'delivery' && item.client?.id === access.caller && item.publishedVersion !== null && !item.versions.find((v) => v.number === item.publishedVersion)?.response };
  if (item.status === 'archived') return null;
  if (item.kind === 'request' && canSubmit && item.requesterId === access.caller) return { ...item, ...common, internalNote: '', alternatives: '', events: [], comments: item.comments.filter((c) => c.audience === 'shared'), versions: [], client: null };
  const version = item.versions.find((v) => v.number === item.publishedVersion);
  if (item.kind !== 'delivery' || item.client?.id !== access.caller || !version) return null;
  return { id: item.id, kind: 'delivery', title: version.title, brief: version.summary, alternatives: '', deadline: '', reviewOn: '', assigneeId: '', createdBy: '', requesterId: '', status: version.response?.status ?? 'in_review', outcome: '', internalNote: '', category: '', priority: '', revision: item.revision, createdAt: version.at, updatedAt: version.at, client: item.client, publishedVersion: version.number, versions: [version], comments: item.comments.filter((c) => c.audience === 'shared'), events: [], ...common, canRespond: !version.response };
}
export function newWork(input: Record<string, unknown>, caller: string, assignee: string, now = new Date().toISOString()): WorkItem {
  if (!['decision', 'delivery', 'request'].includes(String(input.kind))) throw new Error('invalid_work');
  const kind = input.kind as WorkKind;
  return { id: workID(input.id), kind, title: workText(input.title, 160, true), brief: workText(input.brief, 8000, true), alternatives: kind === 'decision' ? workText(input.alternatives ?? '', 4000) : '', deadline: workDate(input.deadline), reviewOn: kind === 'decision' ? workDate(input.reviewOn) : '', assigneeId: assignee, createdBy: caller, requesterId: kind === 'request' ? caller : '', status: kind === 'request' ? 'submitted' : 'draft', outcome: '', internalNote: '', category: workText(input.category ?? '', 80), priority: ['normal', 'urgent'].includes(String(input.priority)) ? String(input.priority) : 'normal', revision: 1, createdAt: now, updatedAt: now, client: null, publishedVersion: null, versions: [], comments: [], events: [{ id: crypto.randomUUID(), actor: caller, action: 'created', at: now }] };
}
/** Authoritative transitions; approval cannot be performed by an arbitrary team member. */
export function transitionWork(item: WorkItem, access: WorkAccess, action: string, text: string): void {
  const manager = managesWork(item, access), decider = access.member && item.assigneeId === access.caller;
  if (action === 'archive' && manager) { item.status = 'archived'; item.publishedVersion = null; return; }
  if (item.kind === 'decision') {
    if (action === 'open' && manager && item.status === 'draft' && item.alternatives.trim() && item.deadline) { item.status = 'discussing'; return; }
    if (action === 'decide' && decider && item.status === 'discussing' && text && item.reviewOn) { item.status = 'decided'; item.outcome = text; return; }
    if (action === 'review' && decider && item.status === 'decided' && text) { item.status = 'reviewed'; item.outcome += `\n\nOutcome review: ${text}`; return; }
  }
  if (item.kind === 'request') {
    const next: Record<string, [string, string[]]> = { triage: ['triaged', ['submitted']], seek_approval: ['awaiting_approval', ['triaged']], approve: ['approved', ['awaiting_approval']], decline: ['declined', ['awaiting_approval']], start: ['in_progress', ['approved']], complete: ['completed', ['in_progress']] };
    const step = next[action];
    if (step && step[1].includes(item.status) && (['approve', 'decline'].includes(action) ? decider && !!text : manager)) { item.status = step[0]; if (text) item.outcome = text; return; }
  }
  throw new Error('invalid_transition');
}
