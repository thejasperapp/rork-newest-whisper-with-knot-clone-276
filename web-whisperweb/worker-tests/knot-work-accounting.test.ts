// @vitest-environment node
// Pure synthetic accounting/receipt cases; no executor or provider calls.
import { describe, expect, it } from 'vitest';
import { shellCommandLimit, shellOperationCost, shellWorkAccounting, remainingShellCommands } from '../../functions/knot-work-budget';
import { commandLedger } from '../../functions/knot-command-ledger';
import { completeSessionSkill, installedSkillRead, skillDataSHA256, verifiedSessionSkill } from '../../functions/knot-session-skills';
import { playableGameRequest, documentRequest, generalArtifactRequest, knotArtifactRouting } from '../../functions/knot-document-proof';
import type { ShellResult } from '../../functions/knot-shell';

describe('work-only runaway protection', () => {
  it('shares a 10000 work ceiling, not twelve ordinary commands', () => {
    expect(shellCommandLimit).toBe(10000);
    expect(remainingShellCommands(40)).toBe(9960);
    expect(remainingShellCommands(10001)).toBe(0);
    for (const operation of ['memory_read','memory_write','skill_index','skill_read','communication_read','workspace_inventory','recovery_read']) expect(shellOperationCost(operation)).toBe(0);
    for (const operation of ['work','workspace_read','skill_draft','unknown',undefined]) expect(shellOperationCost(operation)).toBe(1);
  });
  it('never mislabels historical inclusive counters as work-only', () => {
    expect(shellWorkAccounting('skill_read', 4)).toEqual({ accounting: 'legacy_includes_plumbing', plumbing: true, workCommands: 4, commandLimit: 10000 });
    expect(shellWorkAccounting('skill_read', 4, 'work_v1')).toMatchObject({ accounting: 'work_v1', workCost: 0 });
    expect(shellWorkAccounting(undefined, 5, 'work_v1')).toMatchObject({ workCost: 1 });
  });
});
describe('durable command ledger', () => {
  it('orders actual input/cache receipts per task, not preparation timestamps', () => {
    const records = [
      { id: 'build', taskID: 'a', preparedAt: 1, submitted: true, cached: false },
      { id: 'startup', taskID: 'a', preparedAt: 2, submitted: true, cached: false },
      { id: 'cache', taskID: 'a', preparedAt: 3, submitted: false, cached: true },
      { id: 'prepared', taskID: 'a', preparedAt: 0, submitted: false, cached: false },
      { id: 'old', taskID: 'a', preparedAt: 0, submitted: true, cached: false },
      { id: 'other', taskID: 'b', preparedAt: 0, submitted: true, cached: false },
    ];
    const result = commandLedger(records, [ { proposal_id: 'build', seq: 20, recordedAt: '2026-11-12T01:00:00Z' }, { proposal_id: 'startup', seq: 10 }, { proposal_id: 'cache', seq: 21 }, { proposal_id: 'other', seq: 22 } ]);
    expect(result.get('startup')).toMatchObject({ commandOrder: 1, commandSequence: 10, newExecution: true });
    expect(result.get('build')).toMatchObject({ commandOrder: 2, recordedAt: '2026-11-12T01:00:00Z' });
    expect(result.get('cache')).toEqual({ commandOrder: 3, commandSequence: 21, orderSource: 'persisted_cache_reuse', newExecution: false });
    expect(result.get('other')?.commandOrder).toBe(1);
    expect(result.get('prepared')).toEqual({ orderSource: 'not_dispatched', newExecution: false });
    expect(result.get('old')).toEqual({ orderSource: 'historical_inferred', newExecution: true });
  });
});
describe('complete installed-guide data', () => {
  const command = 'cat /opt/knot-skills/document-creation/SKILL.md';
  it('only permits exact installed read commands, never mutable drafts', () => {
    expect(installedSkillRead(command)).toBe(true);
    for (const value of [command + '; pwd', command + '\n', 'cat -- skills-drafts/guide.md', 'cat /opt/knot-skills/../secret/SKILL.md']) expect(installedSkillRead(value)).toBe(false);
  });
  it('requires complete successful same-session receipts, including full context', () => {
    const result = { sessionID: 'owned', status: 'completed', terminationConfirmed: true, exitCode: 0, outputComplete: true, truncated: false, contextTruncated: false, stdout: 'Complete guide' } as ShellResult;
    expect(completeSessionSkill(result, 'owned')).toBe(true);
    expect(completeSessionSkill(result, 'foreign')).toBe(false);
    for (const change of [{ status: 'uncertain' }, { terminationConfirmed: false }, { exitCode: 1 }, { outputComplete: false }, { truncated: true }, { contextTruncated: true }, { stdout: '' }]) expect(completeSessionSkill({ ...result, ...change } as ShellResult, 'owned')).toBe(false);
  });
  it('binds all cached stdout/stderr and refuses foreign session/command/changed data', async () => {
    const value = { sourceProposalID: 'original', sessionID: 'owned', command, stdout: 'Complete guide', stderr: 'original warning', sha256: await skillDataSHA256('Complete guide', 'original warning'), observedAt: '2026-11-12T00:00:00Z' };
    expect(await verifiedSessionSkill(value, 'owned', command)).toBe(true);
    expect(await verifiedSessionSkill(value, 'foreign', command)).toBe(false);
    expect(await verifiedSessionSkill({ ...value, stderr: 'changed' }, 'owned', command)).toBe(false);
    expect(await verifiedSessionSkill(value, 'owned', command.replace('document-creation', 'computation'))).toBe(false);
  });
});
describe('general creation routing is not a capability whitelist', () => {
  it.each(['Build a family-tree explorer with a document search panel', 'Create an animated HTML birthday card', 'Build a playable game with an inventory report', 'Create a report as an EPUB file', 'Create a document in xyz format'])('routes the requested object through owned general creation: %s', request => {
    expect(generalArtifactRequest(request)).toBe(true);
    expect(documentRequest(request)).toBe(false);
    expect(knotArtifactRouting(request, true)).toMatchObject({ documentTask: false, generalCreate: true });
  });
  it.each(['Create a PDF guide about game design', 'Write a report about RPG combat', 'Create a multi-kilobyte MD file', 'Write a TXT file with game instructions'])('retains specialized proof/raw gates: %s', request => {
    expect(generalArtifactRequest(request)).toBe(false);
    expect(knotArtifactRouting(request, false)).toMatchObject({ documentTask: true, documentFormat: { status: 'bound' } });
  });
  it.each(['What is an EPUB file?', 'Explain SVG format', 'Is xyz format supported?'])('does not treat a format question as creation: %s', request => {
    expect(generalArtifactRequest(request)).toBe(false);
    expect(knotArtifactRouting(request).generalCreate).toBe(false);
  });
  it('binds a novel explicit extension without substituting a document format', () => {
    expect(knotArtifactRouting('Create a document in xyz format', true)).toMatchObject({ artifactFormat: 'xyz', documentTask: false });
    expect(knotArtifactRouting('Create a PDF or DOCX document', true).documentFormat?.status).toBe('ambiguous');
  });
});
describe('playable game request overrides document classification', () => {
  it.each(['Build a playable Pokémon-style HTML RPG with a world map, battles and saves', 'Make a browser game'])('keeps the executable game lane: %s', request => {
    expect(playableGameRequest(request)).toBe(true); expect(documentRequest(request)).toBe(false);
  });
  it.each(['Write a PDF guide about Pokémon-style games', 'Create a report about RPG combat'])('retains explicit documents: %s', request => {
    expect(playableGameRequest(request)).toBe(false); expect(documentRequest(request)).toBe(true);
  });
});
