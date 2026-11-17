// @vitest-environment node
import { describe, expect, it, vi } from 'vitest';
import { foregroundIdentity, foregroundReceiptState, waitForForegroundReceipt, runForegroundSteps } from '../../functions/knot-foreground-turn';
import type { KnotShellProposal } from '../../functions/knot-shell';
const proposal: KnotShellProposal = { id: 'step-1', bot: 'main', conversationID: 'conversation', taskID: 'task', sourceMessageID: 'source', tool: 'session_input', title: 'Synthetic', command: 'never executed', timeoutMs: 1000, expiresAt: 1e15 };
const identity = foregroundIdentity(proposal, 'main', 'conversation', 'task', 'source');
describe('one owned foreground turn', () => {
  it('advances serial steps through one runner only after their handoffs finish', async () => {
    const events: string[] = []; let index = 0;
    await runForegroundSteps(async () => { events.push('select-' + index); return index < 3 ? { ...proposal, id: String(index++) } : undefined; }, async p => { await Promise.resolve(); events.push('receipt-' + p.id); }, new AbortController().signal, 12);
    expect(events).toEqual(['select-0', 'receipt-0', 'select-1', 'receipt-1', 'select-2', 'receipt-2', 'select-3']);
  });
  it.each(['bot', 'conversationID', 'taskID', 'sourceMessageID'] as const)('rejects a proposal with foreign %s', field => {
    expect(() => foregroundIdentity({ ...proposal, [field]: 'foreign' }, 'main', 'conversation', 'task', 'source')).toThrow('owned_receipt_unavailable');
  });
  it('waits only for exact persisted identity and never executes work', async () => {
    let reads = 0, pauses = 0;
    await waitForForegroundReceipt(identity, async () => ({ ...identity, state: ++reads === 2 ? 'ready' : 'waiting' }), new AbortController().signal, Date.now() + 10000, async () => { pauses++; });
    expect(reads).toBe(2); expect(pauses).toBe(1);
    await expect(waitForForegroundReceipt(identity, async () => ({ ...identity, taskID: 'foreign', state: 'ready' }), new AbortController().signal, Date.now() + 10000)).rejects.toThrow('owned_receipt_unavailable');
  });
  it.each(['cancelled', 'uncertain'] as const)('stops at persisted %s without a subsequent step', async state => {
    const read = vi.fn(async () => ({ ...identity, state }));
    await expect(waitForForegroundReceipt(identity, read, new AbortController().signal, Date.now() + 10000)).rejects.toThrow('foreground_execution_unconfirmed');
    expect(read).toHaveBeenCalledTimes(1);
  });
  it('honors cancellation before selection and during the readiness read', async () => {
    const controller = new AbortController(); controller.abort(); const step = vi.fn();
    await expect(runForegroundSteps(step, vi.fn(), controller.signal, 12)).rejects.toThrow('cancelled'); expect(step).not.toHaveBeenCalled();
    const during = new AbortController();
    await expect(waitForForegroundReceipt(identity, async () => { during.abort(); return { ...identity, state: 'ready' }; }, during.signal, Date.now() + 10000)).rejects.toThrow('cancelled');
  });
  it('cannot advance after the overall deadline even when ready arrives', async () => {
    vi.useFakeTimers();
    try {
      vi.setSystemTime(1000);
      await expect(waitForForegroundReceipt(identity, async () => { vi.setSystemTime(2001); return { ...identity, state: 'ready' }; }, new AbortController().signal, 2000)).rejects.toThrow('foreground_turn_expired');
    } finally { vi.useRealTimers(); }
  });
  it('prevents replay and enforces an explicitly supplied work ceiling', async () => {
    const handoff = vi.fn(async () => {});
    await expect(runForegroundSteps(async () => proposal, handoff, new AbortController().signal, 12)).rejects.toThrow('foreground_step_limit_or_replay'); expect(handoff).toHaveBeenCalledTimes(1);
    let n = 0; const bounded = vi.fn(async () => {});
    await expect(runForegroundSteps(async () => ({ ...proposal, id: String(n++) }), bounded, new AbortController().signal, 12)).rejects.toThrow('foreground_step_limit_or_replay'); expect(bounded).toHaveBeenCalledTimes(12);
  });
  it('continues beyond twelve commands and keeps plumbing unmetered', async () => {
    let index = 0; const handed: string[] = [];
    await runForegroundSteps(async () => index < 36 ? { ...proposal, id: String(index++), operation: index % 2 ? 'skill_read' : 'work' } : undefined, async p => { handed.push(p.id); }, new AbortController().signal, 18);
    expect(handed).toHaveLength(36);
    expect(handed.at(-1)).toBe('35');
  });
  it('requires immutable command log retention before readiness', () => {
    const record = { cancelled: false, phase: 'finished', hasSession: true, hasFinalLog: true, hasRetainedLog: true, terminationConfirmed: true, outputComplete: true, truncated: false };
    expect(foregroundReceiptState(record)).toBe('ready');
    expect(foregroundReceiptState({ ...record, hasFinalLog: false })).toBe('waiting');
    expect(foregroundReceiptState({ ...record, hasRetainedLog: false })).toBe('waiting');
    expect(foregroundReceiptState({ ...record, truncated: true })).toBe('uncertain');
    expect(foregroundReceiptState({ ...record, outputComplete: false })).toBe('uncertain');
    expect(foregroundReceiptState({ ...record, cancelled: true })).toBe('cancelled');
    expect(foregroundReceiptState({ ...record, phase: 'uncertain' })).toBe('uncertain');
  });
});
