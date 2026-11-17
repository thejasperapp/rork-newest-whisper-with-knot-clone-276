// @vitest-environment node
// Synthetic acceptance receipts only: no credentials, files or service calls.
import { describe, expect, it } from 'vitest';
import { createHash } from 'node:crypto';
import { AcceptanceSkillProvenance } from '../../scripts/knot-acceptance-provenance';
const id = (n: number) => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');
function fixture() {
  const owner = { accountID: id(1), workspaceID: 'whisper-' + id(1) };
  const turn = { requestID: id(2), conversationID: id(3), sourceMessageID: id(4) };
  const proposal = { id: id(5), bot: 'main', ...turn, taskID: turn.requestID, command: 'cat /opt/knot-skills/document-creation/SKILL.md' };
  const original = { proposalID: proposal.id, bot: 'main', conversationID: turn.conversationID, sessionID: id(6), status: 'completed', exitCode: 0, terminationConfirmed: true, outputComplete: true, truncated: false, contextTruncated: false, stdout: 'Complete installed guide 🙂', stderr: 'warning', providerReceipt: { session_id: id(6), user_id: owner.workspaceID, output_complete: true, output_late_bytes: 0 }, commandReceipt: { source: 'harness_shell_boundaries_v1', session_id: id(6), proposal_id: proposal.id, stdout_start: 0, stdout_end: 32, stderr_start: 0, stderr_end: 7, exit_code: 0, background_jobs: false, started_at: '2026-11-13T00:00:00.000Z', observed_finished_at: '2026-11-13T00:00:01.000Z' } };
  const nextTurn = { requestID: id(7), conversationID: id(8), sourceMessageID: id(9) };
  const cachedProposal = { ...proposal, ...nextTurn, taskID: nextTurn.requestID, id: id(10) };
  const { commandReceipt: _receipt, providerReceipt: _provider, ...data } = original;
  const cached = { ...data, proposalID: cachedProposal.id, conversationID: nextTurn.conversationID, cachedData: { source: 'session_skill_cache_v1', sourceProposalID: proposal.id, observedAt: original.commandReceipt.observed_finished_at, newExecution: false, sha256: createHash('sha256').update(JSON.stringify([original.stdout, original.stderr])).digest('hex') } };
  const ledger = new AcceptanceSkillProvenance(owner);
  return { ledger, turn, proposal, original, nextTurn, cachedProposal, cached };
}
describe('acceptance cached installed-guide provenance', () => {
  it('reuses complete known originals across asks without fabricating execution', () => {
    const f = fixture();
    f.ledger.remember(f.proposal, f.original, f.turn);
    expect(f.ledger.acceptCache(f.cachedProposal, f.cached, f.nextTurn)).toBe(true);
    expect(f.cached).not.toHaveProperty('commandReceipt');
    expect(f.ledger.acceptCache(f.proposal, f.original, f.turn)).toBe(false);
  });
  it('never accepts unknown provenance or seeds from a cache', () => {
    const f = fixture();
    f.ledger.remember(f.cachedProposal, f.cached, f.nextTurn);
    expect(() => f.ledger.acceptCache(f.cachedProposal, f.cached, f.nextTurn)).toThrow('cached_skill_provenance_unconfirmed');
  });
  it.each(['session', 'command', 'stdout', 'stderr', 'hash', 'time', 'source', 'execution', 'receipt', 'provider', 'incomplete', 'truncated', 'context', 'exit', 'termination', 'conversation', 'task', 'newline'] as const)('rejects changed cache binding: %s', change => {
    const f = fixture(); f.ledger.remember(f.proposal, f.original, f.turn);
    const p: Record<string, any> = structuredClone(f.cachedProposal), r: Record<string, any> = structuredClone(f.cached);
    if (change === 'session') r.sessionID = id(11);
    if (change === 'command') p.command = p.command.replace('document-creation', 'other');
    if (change === 'newline') p.command += '\n';
    if (change === 'stdout' || change === 'stderr') r[change] += ' changed';
    if (change === 'hash') r.cachedData.sha256 = 'f'.repeat(64);
    if (change === 'time') r.cachedData.observedAt = '2026-11-13T00:00:01.001Z';
    if (change === 'source') r.cachedData.sourceProposalID = id(11);
    if (change === 'execution') r.cachedData.newExecution = true;
    if (change === 'receipt') r.commandReceipt = f.original.commandReceipt;
    if (change === 'provider') r.providerReceipt = f.original.providerReceipt;
    if (change === 'incomplete') r.outputComplete = false;
    if (change === 'truncated') r.truncated = true;
    if (change === 'context') r.contextTruncated = true;
    if (change === 'exit') r.exitCode = 1;
    if (change === 'termination') r.terminationConfirmed = false;
    if (change === 'conversation') r.conversationID = id(11);
    if (change === 'task') p.taskID = id(11);
    expect(() => f.ledger.acceptCache(p, r, f.nextTurn)).toThrow();
  });
  it.each(['owner', 'late', 'incomplete', 'receipt', 'range', 'time', 'context'] as const)('rejects unproven originals before caching: %s', change => {
    const f = fixture(), r = structuredClone(f.original);
    if (change === 'owner') r.providerReceipt.user_id = 'foreign';
    if (change === 'late') r.providerReceipt.output_late_bytes = 1;
    if (change === 'incomplete') r.outputComplete = false;
    if (change === 'receipt') r.commandReceipt.proposal_id = id(11);
    if (change === 'range') r.commandReceipt.stdout_start = -1;
    if (change === 'time') r.commandReceipt.observed_finished_at = 'not a timestamp';
    if (change === 'context') r.contextTruncated = true;
    expect(() => f.ledger.remember(f.proposal, r, f.turn)).toThrow();
    expect(() => f.ledger.acceptCache(f.cachedProposal, f.cached, f.nextTurn)).toThrow();
  });
});
