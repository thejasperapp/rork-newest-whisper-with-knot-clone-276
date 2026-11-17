/** Server-owned authored operation state. No placeholder or stale closed label.
 * Header shows the latest actual open operation after 800 ms; history preserves
 * short operations too. Presentation never establishes execution or quality. */
export const knotActivityMinimumMs = 800;
export const knotActivityPlaceholder = 'Working on your request';

export type KnotOpenActivity = { id: string; label: string; tool: string; startedAt: number; purpose?: string };
export type KnotActivityEntry = { id: string; label: string; tool: string; started_at: number; ended_at: number | null; receipt_id: string | null; purpose?: string; result?: string };
export type KnotActivityState = { open: KnotOpenActivity[]; closed: KnotActivityEntry[]; placeholderUsed: boolean };
export type KnotCurrentActivity = { turnID: string; activityID: string; label: string; source: { tool: string; receiptID: string | null }; startedAt: number; endedAt: number | null };

const cleanLabel = (value: unknown): string | undefined => typeof value === 'string' && value.trim() && value.length <= 60 && !/[\x00-\x1f<>`]/.test(value) ? value : undefined;
const cleanText = (value: unknown, limit: number): string | undefined => typeof value === 'string' && value.length <= limit && !/[\x00-\x1f<>`]/.test(value) ? value.trim() || undefined : undefined;
const cleanID = (value: unknown): string | undefined => typeof value === 'string' && /^[A-Za-z0-9:._-]{1,120}$/.test(value) ? value : undefined;

export function emptyKnotActivity(): KnotActivityState { return { open: [], closed: [], placeholderUsed: false }; }

function close(state: KnotActivityState, id: string, now: number, receiptID?: string, result?: string): void {
  const index = state.open.findIndex(a => a.id === id);
  if (index < 0) return;
  const [activity] = state.open.splice(index, 1);
  if (activity.id === 'placeholder') return;
  state.closed.push({ id: activity.id, label: activity.label, tool: activity.tool, purpose: activity.purpose, result, started_at: activity.startedAt, ended_at: now, receipt_id: receiptID ?? null });
  if (state.closed.length > 80) state.closed.splice(0, state.closed.length - 80);
}

/** Called once when the owned turn begins running. */
export function startKnotActivity(state: KnotActivityState, _now = Date.now()): KnotActivityState {
  // No placeholder and no retained label from older deployments.
  state.placeholderUsed = true;
  state.open = state.open.filter(a => a.id !== 'placeholder');
  return state;
}

/** Applies a knot-live `currentActivity` frame. Unknown shapes are ignored. */
export function applyKnotActivityFrame(state: KnotActivityState, value: unknown, now = Date.now()): boolean {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const frame = value as Record<string, unknown>;
  const id = cleanID(frame.activityID);
  if (!id || id === 'placeholder') return false;
  if (frame.phase === 'open') {
    const label = cleanLabel(frame.label);
    if (!label || state.open.some(a => a.id === id) || state.open.length >= 16) return false;
    close(state, 'placeholder', now);
    state.open.push({ id, label, tool: cleanID(frame.tool) ?? 'work', startedAt: now, purpose: typeof frame.purpose === 'string' && frame.purpose.trim() && cleanText(frame.purpose, 300) ? frame.purpose : undefined });
    return true;
  }
  if (frame.phase === 'close') { close(state, id, now, cleanID(frame.receiptID), cleanText(frame.result, 600)); return true; }
  if (frame.phase === 'result') {
    const entry = state.closed.find(a => a.id === id), result = cleanText(frame.result, 600);
    if (!entry || !result) return false;
    entry.result = result;
    return true;
  }
  return false;
}

/** Closes everything at turn end so the timeline records true end times. */
export function finishKnotActivity(state: KnotActivityState, now = Date.now()): KnotActivityState {
  for (const activity of [...state.open]) close(state, activity.id, now);
  return state;
}

/** The label to show now, derived without mutating stored state. */
export function currentKnotActivity(state: KnotActivityState | undefined, turnID: string, terminal: boolean, now = Date.now()): KnotCurrentActivity | null {
  if (!state || terminal) return null;
  const visible = state.open.filter(a => a.id !== 'placeholder' && now - a.startedAt >= knotActivityMinimumMs).sort((a, b) => b.startedAt - a.startedAt)[0];
  if (visible) return { turnID, activityID: visible.id, label: visible.label, source: { tool: visible.tool, receiptID: null }, startedAt: visible.startedAt, endedAt: null };
  return null;
}

/** Ordered timeline for acceptance: closed entries plus open ones that have
 * already been visible for at least the minimum duration. */
export function knotActivityTimeline(state: KnotActivityState | undefined, now = Date.now()): KnotActivityEntry[] {
  if (!state) return [];
  const open = state.open.filter(a => now - a.startedAt >= knotActivityMinimumMs).map(a => ({ id: a.id, label: a.label, tool: a.tool, purpose: a.purpose, started_at: a.startedAt, ended_at: null, receipt_id: null }));
  return [...state.closed, ...open].sort((a, b) => a.started_at - b.started_at);
}
