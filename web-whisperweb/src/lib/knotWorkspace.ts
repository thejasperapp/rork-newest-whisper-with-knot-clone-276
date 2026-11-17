import { validKnotReaction } from '@/lib/knotReactions';
import { validKnotDocuments, type KnotDocument } from '@/lib/knotDocuments';
import { groupThemeSession } from '@/lib/groupThemeSession';
import { knotBackendOrigin } from '@/lib/knotBackend';
import { consentChanged, knotAllowed, KnotHTTPError, type KnotBot } from '@/lib/knotService';

export interface KnotWorkspaceRecord {
  spec: { id: string; bot: KnotBot; conversationID: string; title: string; command: string; timeoutMs: number; expiresAt: number };
  taskID?: string; taskTitle?: string; sourceMessageID?: string; recordedAt?: string; operation?: string; state: string;
  receiptOutputComplete?: boolean; receiptTruncated?: boolean;
  result: { proposalID: string; bot: KnotBot; conversationID: string; status: string; stdout: string; stderr: string; exitCode: number | null; outputComplete: boolean; truncated: boolean; terminationConfirmed: boolean; reason: string; sessionID?: string; providerStatus?: string; providerReceipt?: unknown; commandReceipt?: unknown; providerStartedAt?: string; providerEndedAt?: string; durationMs?: number };
}
export interface KnotRecordedActivity { messageID?: string; emoji?: string; revision?: number; id: string; requestID: string; taskID?: string; sourceMessageID?: string; sequence: number; kind: string; label: string; recordedAt: string }
export interface KnotTaskMessage { id: string; createdAt?: number; role: 'user' | 'ember'; text: string }
export interface KnotWorkspaceReplay { records: KnotWorkspaceRecord[]; events: unknown[]; retentionHours: number; activities?: KnotRecordedActivity[]; documents?: KnotDocument[] }
export interface KnotWorkspaceTask { id: string; title: string; date: number; records: KnotWorkspaceRecord[]; activities: KnotRecordedActivity[]; messages: KnotTaskMessage[] }
const uuid = (value: unknown): value is string => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const validMessageLink = (value: unknown) => value === undefined || (typeof value === 'string' && value.length > 0 && value.length <= 128);

/** Read-only evidence transport. No execution, input, retry or permission grant path. */
export async function readKnotWorkspace(owner: string, action: 'events' | 'log' | 'capabilities', bot: KnotBot, conversationID: string, signal: AbortSignal, proposalID?: string): Promise<unknown> {
  if (!uuid(conversationID) || (proposalID !== undefined && !uuid(proposalID))) throw new Error('Invalid context');
  const withdrawal = new AbortController();
  const stop = () => withdrawal.abort();
  const stored = (event: StorageEvent) => { if (event.key === null || event.key.startsWith(`knot_ai_consent_v3:${owner.toLowerCase()}`)) stop(); };
  window.addEventListener(consentChanged, stop); window.addEventListener('storage', stored);
  const auth = await groupThemeSession(owner).catch(error => { window.removeEventListener(consentChanged, stop); window.removeEventListener('storage', stored); throw error; });
  const combined = AbortSignal.any([auth.signal, signal, withdrawal.signal, AbortSignal.timeout(25000)]);
  const check = () => { auth.check(); if (combined.aborted || !knotAllowed(owner)) throw new DOMException('Stopped', 'AbortError'); };
  let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
  try {
    check();
    const response = await fetch(knotBackendOrigin + '/knot/shell/' + action, {
      method: action === 'capabilities' ? 'GET' : 'POST', redirect: 'error', cache: 'no-store', signal: combined,
      headers: { 'Content-Type': 'application/json', 'X-Whisper-Authorization': `Bearer ${auth.token}` },
      body: action === 'capabilities' ? undefined : JSON.stringify({ bot, conversationID: conversationID.toLowerCase(), ...(proposalID ? { proposalID } : {}) }),
    });
    check();
    if (!response.ok || !response.body) { await response.body?.cancel(); throw new KnotHTTPError(response.status); }
    reader = response.body.getReader();
    const decoder = new TextDecoder('utf-8', { fatal: true }); let text = '', size = 0;
    const limit = action === 'capabilities' ? 100000 : 6500000;
    for (;;) { const part = await reader.read(); check(); if (part.done) break; size += part.value.byteLength; if (size > limit) throw new Error('Evidence too large'); text += decoder.decode(part.value, { stream: true }); }
    text += decoder.decode(); check();
    const value: unknown = JSON.parse(text);
    if (action === 'events') {
      const replay = value as KnotWorkspaceReplay;
      if (replay?.documents !== undefined && !validKnotDocuments(replay.documents)) throw new Error('Invalid documents');
      if (replay?.activities !== undefined && (!Array.isArray(replay.activities) || replay.activities.length > 400 || replay.activities.some(a => !a || typeof a.id !== 'string' || !uuid(a.requestID) || (a.taskID !== undefined && !uuid(a.taskID)) || !validMessageLink(a.sourceMessageID) || ((a.kind === 'reaction_placed' || a.kind === 'reaction_replaced') && (!validKnotReaction({ messageID: a.messageID, emoji: a.emoji, revision: a.revision, recordedAt: a.recordedAt }) || a.messageID !== a.sourceMessageID)) || !Number.isSafeInteger(a.sequence) || typeof a.kind !== 'string' || typeof a.label !== 'string' || a.label.length > 120 || !Number.isFinite(Date.parse(a.recordedAt))))) throw new Error('Invalid activity');
      if (!replay || !Array.isArray(replay.records) || replay.records.length > 40 || !Array.isArray(replay.events) || replay.records.some(r =>
        !r?.spec || !uuid(r.spec.id) || r.spec.bot !== bot || r.spec.conversationID !== conversationID.toLowerCase() ||
        typeof r.spec.title !== 'string' || typeof r.spec.command !== 'string' || !Number.isFinite(r.spec.expiresAt) ||
        (r.taskID !== undefined && !uuid(r.taskID)) || (r.taskTitle !== undefined && (typeof r.taskTitle !== 'string' || r.taskTitle.length > 160)) || !validMessageLink(r.sourceMessageID) ||
        !r.result || r.result.proposalID !== r.spec.id || r.result.bot !== bot || r.result.conversationID !== conversationID.toLowerCase() ||
        typeof r.result.stdout !== 'string' || typeof r.result.stderr !== 'string' || typeof r.result.reason !== 'string' ||
        typeof r.result.terminationConfirmed !== 'boolean' || typeof r.result.outputComplete !== 'boolean' || typeof r.result.truncated !== 'boolean')) throw new Error('Invalid evidence');
    }
    return value;
  } finally {
    await reader?.cancel().catch(() => undefined); reader?.releaseLock(); auth.dispose();
    window.removeEventListener(consentChanged, stop); window.removeEventListener('storage', stored);
  }
}

export function knotStepStatus(record: KnotWorkspaceRecord): string {
  const result = record.result;
  if (result.status === 'cancelled') return result.terminationConfirmed ? (result.sessionID ? 'Stopped' : 'Not started') : 'Stop requested';
  if (result.status === 'awaiting_approval') return 'Not started';
  if (!result.terminationConfirmed) return result.status === 'stopping' ? 'Stop requested' : result.providerStatus === 'live' ? 'Working' : 'Not confirmed';
  if (!result.sessionID) return 'Not started';
  if (result.status === 'failed' || (result.exitCode !== null && result.exitCode !== 0)) return 'Failed';
  if (!(record.receiptOutputComplete ?? result.outputComplete) || (record.receiptTruncated ?? result.truncated)) return 'Output incomplete';
  return result.status === 'completed' && result.exitCode === 0 ? 'Step finished' : 'Ended';
}
export function knotWorkspaceTasks(records: KnotWorkspaceRecord[], activities: KnotRecordedActivity[] = [], messages: KnotTaskMessage[] = []): KnotWorkspaceTask[] {
  const tasks = new Map<string, KnotWorkspaceTask>();
  let question: string | undefined;
  // Pair messages by their real chat order. Never merge repeated question text
  // or assign execution ownership from nearby timestamps.
  for (const message of new Map(messages.map(m => [m.id.toLowerCase(), m])).values()) {
    if (message.role === 'user') question = 'message:' + message.id.toLowerCase();
    const id = question ?? 'message:' + message.id.toLowerCase();
    if (!tasks.has(id)) tasks.set(id, { id, title: message.role === 'user' ? message.text : 'Conversation task', date: message.createdAt ?? 0, records: [], activities: [], messages: [] });
    tasks.get(id)!.messages.push(message);
  }
  const groups = new Map<string, { records: KnotWorkspaceRecord[]; activities: KnotRecordedActivity[] }>();
  const group = (id: string) => { const key = id.toLowerCase(); if (!groups.has(key)) groups.set(key, { records: [], activities: [] }); return groups.get(key)!; };
  for (const record of new Map(records.map(r => [r.spec.id.toLowerCase(), r])).values()) group(record.taskID ?? record.spec.id).records.push(record);
  for (const activity of new Map(activities.map(a => [a.id, a])).values()) group(activity.taskID ?? activity.requestID).activities.push(activity);
  for (const [root, group] of groups) {
    group.records.sort((a,b) => a.spec.expiresAt - b.spec.expiresAt || a.spec.id.localeCompare(b.spec.id));
    group.activities.sort((a,b) => Date.parse(a.recordedAt) - Date.parse(b.recordedAt) || (a.requestID === b.requestID ? a.sequence - b.sequence : a.id.localeCompare(b.id)));
    const source = group.records.find(r => r.sourceMessageID)?.sourceMessageID ?? group.activities.find(a => a.sourceMessageID)?.sourceMessageID;
    const linked = source ? 'message:' + source.toLowerCase() : undefined;
    const id = linked && tasks.has(linked) ? linked : 'task:' + root;
    if (!tasks.has(id)) tasks.set(id, { id, title: group.records[0]?.taskTitle ?? (group.activities.some(a => a.kind.startsWith('browser_')) ? 'Browser task' : 'Conversation task'), date: group.records[0] ? group.records[0].spec.expiresAt - 600000 : Date.parse(group.activities[0]?.recordedAt ?? '') || 0, records: [], activities: [], messages: [] });
    const task = tasks.get(id)!;
    task.records.push(...group.records); task.activities.push(...group.activities);
  }
  for (const task of tasks.values()) {
    task.records.sort((a,b) => a.spec.expiresAt - b.spec.expiresAt || a.spec.id.localeCompare(b.spec.id));
    task.activities.sort((a,b) => Date.parse(a.recordedAt) - Date.parse(b.recordedAt) || (a.requestID === b.requestID ? a.sequence - b.sequence : a.id.localeCompare(b.id)));
  }
  return [...tasks.values()].sort((a,b) => b.date - a.date || a.id.localeCompare(b.id));
}
export function knotTaskStatus(task: KnotWorkspaceTask): string {
  const labels = task.records.map(knotStepStatus);
  for (const label of ['Working', 'Stop requested', 'Not confirmed']) if (labels.includes(label)) return label;
  const last = task.activities[task.activities.length - 1];
  if (last && ['error', 'rejected', 'cancelled', 'browser_action_uncertain'].includes(last.kind)) return last.label;
  const count = labels.filter(label => label === 'Step finished').length;
  const failed = labels.filter(label => label === 'Failed' || label === 'Output incomplete').length;
  if (failed) return `${count} steps finished · ${failed} need attention`;
  if (labels.length) return count ? `${count} ${count === 1 ? 'step' : 'steps'} finished` : labels[labels.length - 1];
  return last?.label ?? (task.messages.some(m => m.role === 'ember') ? 'Reply saved' : 'Message saved');
}
