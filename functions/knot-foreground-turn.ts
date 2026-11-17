import type { KnotShellProposal } from './knot-shell';
import { shellOperationCost } from './knot-work-budget';

type Identity = { proposalID: string; taskID: string; sourceMessageID: string; bot: string; conversationID: string };
export type ForegroundReadiness = Identity & { state: 'waiting' | 'ready' | 'cancelled' | 'uncertain' };
export function foregroundIdentity(proposal: KnotShellProposal, bot: string, conversationID: string, taskID: string, sourceMessageID: string): Identity {
  if (proposal.bot !== bot || proposal.conversationID !== conversationID || proposal.taskID !== taskID || proposal.sourceMessageID !== sourceMessageID) throw new Error('owned_receipt_unavailable');
  return { proposalID: proposal.id, taskID, sourceMessageID, bot, conversationID };
}
/** Persisted state only; never initiates provider recovery. */
export function foregroundReceiptState(record: { cancelled: boolean; phase: string; hasSession: boolean; hasFinalLog: boolean; hasRetainedLog: boolean; terminationConfirmed?: boolean; outputComplete?: boolean; truncated?: boolean }): ForegroundReadiness['state'] {
  if (record.cancelled) return 'cancelled';
  if (record.phase === 'uncertain') return 'uncertain';
  if (record.phase !== 'finished' || !record.terminationConfirmed) return 'waiting';
  if (!record.hasSession) return 'ready';
  if (!record.hasFinalLog || !record.hasRetainedLog) return 'waiting';
  return record.outputComplete && !record.truncated ? 'ready' : 'uncertain';
}
function check(signal: AbortSignal) { if (signal.aborted) throw new Error('cancelled'); }
async function pause(signal: AbortSignal): Promise<void> {
  check(signal);
  await new Promise<void>((resolve, reject) => {
    const abort = () => { clearTimeout(timer); reject(new Error('cancelled')); };
    const timer = setTimeout(() => { signal.removeEventListener('abort', abort); resolve(); }, 650);
    signal.addEventListener('abort', abort, { once: true });
  });
}
/** Small persisted reads only. A timeout or unknown ownership never restarts work. */
export async function waitForForegroundReceipt(identity: Identity, read: () => Promise<ForegroundReadiness>, signal: AbortSignal, expiresAt: number, wait = pause): Promise<void> {
  for (;;) {
    check(signal);
    if (Date.now() >= expiresAt) throw new Error('foreground_turn_expired');
    const receipt = await read();
    check(signal);
    if (Date.now() >= expiresAt) throw new Error('foreground_turn_expired');
    if (Object.entries(identity).some(([key, value]) => receipt[key as keyof Identity] !== value)) throw new Error('owned_receipt_unavailable');
    if (receipt.state === 'ready') return;
    if (receipt.state !== 'waiting') throw new Error('foreground_execution_unconfirmed');
    await wait(signal);
  }
}
/** One stream owns all steps. No recursive HTTP, new admission or replay. */
export async function runForegroundSteps(step: () => Promise<KnotShellProposal | undefined>, handoff: (proposal: KnotShellProposal) => Promise<void>, signal: AbortSignal, limit: number): Promise<void> {
  const seen = new Set<string>();
  let work = 0;
  for (;;) {
    check(signal);
    const proposal = await step();
    check(signal);
    if (!proposal) return;
    const cost = shellOperationCost(proposal.operation);
    if (seen.has(proposal.id) || cost > 0 && work >= limit) throw new Error('foreground_step_limit_or_replay');
    seen.add(proposal.id);
    work += cost;
    await handoff(proposal);
  }
}
