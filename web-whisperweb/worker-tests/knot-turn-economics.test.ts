// @vitest-environment node
import { describe, expect, it, vi } from 'vitest';
vi.mock('cloudflare:workers', () => ({ DurableObject: class {} }));
import { knotAuthoringBudgetMs, knotCreationTurnMs, knotOrdinaryTurnMs, knotTurnEconomics, knotAuthorPromptTargetBytes, knotCreationBudget, knotCreationSizeClass, knotCreationSizeClasses } from '../../functions/knot-turn-economics';
import { documentAuthoringContext, documentSliceInstruction, documentSliceTokenLimit } from '../../functions/knot-document-authoring-context';
import { documentAuthoringResponseFormat } from '../../functions/knot-document-authoring';
import { safeKnotActivityDetail } from '../../functions/knot-activity';
import type { ShellWorkflow, ShellEvidence } from '../../functions/knot-shell';
const workflow: ShellWorkflow = { rootID: 'synthetic-owned', parentID: 'synthetic-parent', sourceMessageID: 'synthetic-source', originalRequest: 'Create a PDF using all of the complete reference', mode: 'Create', documentTask: true, memoryRead: true, indexRead: true, skills: [], commands: 3, memoryWritten: false };
const complete = { status: 'completed', exitCode: 0, terminationConfirmed: true, outputComplete: true, truncated: false, contextTruncated: false };
const size = (value: unknown) => Buffer.byteLength(JSON.stringify(value));
describe('throughput-coupled creation economics and author-only context', () => {
  it('pays the whole byte ceiling at a conservative measured rate with a margin', () => {
    const e = knotTurnEconomics;
    expect(e.budgetBytesPerSecond).toBeLessThanOrEqual(e.calibrationBytes / (e.calibrationElapsedMs / 1000));
    expect(knotAuthoringBudgetMs).toBeGreaterThanOrEqual(e.programByteCeiling / e.budgetBytesPerSecond * (e.marginPermille / 1000) * 1000);
    expect(knotAuthoringBudgetMs).toBe(555000);
    expect(knotCreationTurnMs).toBe(knotAuthoringBudgetMs + e.completionReserveMs);
    expect(knotOrdinaryTurnMs).toBe(285000);
    expect(documentSliceTokenLimit(64000)).toBeLessThanOrEqual(128000);
    expect(documentSliceTokenLimit(2000)).toBeLessThanOrEqual(16384);
    expect(documentAuthoringResponseFormat(2000).json_schema.schema.properties.code).toHaveProperty('maxLength', 2000);
    expect(documentAuthoringResponseFormat(64000).json_schema.schema.properties.code).not.toHaveProperty('maxLength');
  });
  it('funds each actual admitted size class without guessing a smaller content ceiling', () => {
    for (const sizeClass of Object.keys(knotCreationSizeClasses) as (keyof typeof knotCreationSizeClasses)[]) {
      const budget = knotCreationBudget(sizeClass);
      expect(budget.authoringBudgetMs).toBeGreaterThanOrEqual(budget.programByteCeiling / budget.budgetBytesPerSecond * budget.marginPermille);
      expect(budget.turnBudgetMs).toBe(budget.authoringBudgetMs + budget.completionReserveMs);
    }
    expect(knotCreationSizeClass({ documentTask: true })).toBe('document_program_74kb');
    expect(knotCreationSizeClass({ artifactFormat: 'html' })).toBe('document_program_74kb');
    expect(knotCreationSizeClass({})).toBe('workspace_command_12kb');
    expect(knotCreationBudget('workspace_command_12kb').turnBudgetMs).toBe(450000);
  });
  it('interns exact read bytes even when receipt completeness differs, preserving both outcomes', () => {
    const stdout = 'Complete original reference\n'.repeat(1000);
    const receipt = { ...complete, proposalID: 'latest', operation: 'workspace_read', stdout, stderr: '', contextTruncated: true, evidence: [{ ...complete, proposalID: 'original', operation: 'workspace_read', stdout, stderr: '' }] } as unknown as ShellEvidence;
    const messages = documentAuthoringContext({ conversation: [], workflow, receipt, craftGuidance: '' });
    const ledger = JSON.parse(String(messages.find(m => typeof m.content === 'string' && m.content.startsWith('COMPLETE LIVE GUIDANCE'))!.content).split('\n').slice(1).join('\n'));
    expect(ledger.reads).toHaveLength(2);
    expect(ledger.reads.map((r: any) => r.contextTruncated)).toEqual([false, true]);
    expect(ledger.reads.every((r: any) => r.payload === 0)).toBe(true);
    expect(messages.filter(m => typeof m.content === 'string' && m.content.endsWith('\n' + stdout))).toHaveLength(1);
  });
  it('deduplicates exact read bytes across proposal identities without losing provenance or memory', () => {
    const reference = 'Required complete reference 🙂\n'.repeat(300);
    const read = { ...complete, operation: 'workspace_read', reviewedCommand: 'cat -- reference.md', stdout: reference, stderr: '' };
    const receipt = { ...read, proposalID: 'latest', evidence: [
      { ...read, proposalID: 'earlier' },
      { ...complete, operation: 'memory_read', proposalID: 'memory', stdout: 'Original preference: no peanuts.', stderr: '' },
      { ...complete, operation: 'work', proposalID: 'build', stdout: 'DISCARD_WRAPPER_OUTPUT'.repeat(2000), providerReceipt: { raw: 'DISCARD_PROVIDER_JSON' }, reviewedCommand: 'DISCARD_EXECUTOR_WRAPPER', documentInvocation: { stage: 'source', path: 'prior.html', code: 'PRESERVE_COMPLETE_DEVELOPED_SOURCE' } },
    ] } as unknown as ShellEvidence;
    const messages = documentAuthoringContext({ conversation: [{ role: 'user', content: 'Complete original conversation.' }], workflow, receipt, craftGuidance: 'Complete craft guidance.' });
    const ledger = JSON.parse(String(messages.find(m => typeof m.content === 'string' && m.content.startsWith('COMPLETE LIVE GUIDANCE'))!.content).split('\n').slice(1).join('\n'));
    expect(ledger.reads.find((r: any) => r.operation === 'workspace_read').proposalIDs).toEqual(['earlier', 'latest']);
    expect(messages.filter(m => typeof m.content === 'string' && m.content.endsWith('\n' + reference))).toHaveLength(1);
    expect(ledger.reads).toContainEqual(expect.objectContaining({ operation: 'memory_read', payload: 1 }));
    expect(messages.some(m => typeof m.content === 'string' && m.content.endsWith('\nOriginal preference: no peanuts.'))).toBe(true);
    expect(JSON.stringify(messages)).toContain('PRESERVE_COMPLETE_DEVELOPED_SOURCE');
    expect(JSON.stringify(messages)).not.toMatch(/DISCARD_WRAPPER_OUTPUT|DISCARD_PROVIDER_JSON|DISCARD_EXECUTOR_WRAPPER/);
    expect(size(messages)).toBeLessThanOrEqual(knotAuthorPromptTargetBytes);
    // This is not a cap on indispensable references or exact continuation bytes.
    const instruction = documentSliceInstruction({ stage: 'source', interpreter: 'python3', path: 'fresh.html', title: '', deliveryLabel: '', authoring: 'author' }, '#'.repeat(40000), 7, { attempt: 1, requestedCharacters: 64000, schemaHash: 'a'.repeat(64) });
    expect(size([...messages, { role: 'system', content: instruction }])).toBeGreaterThan(knotAuthorPromptTargetBytes);
    expect(instruction.endsWith(JSON.stringify('#'.repeat(40000)))).toBe(true);
  });
  it('retains over-target indispensable input whole and exposes only honest numeric diagnostics', () => {
    const reference = 'Required reference with no clipping.\n'.repeat(2000);
    const receipt = { ...complete, proposalID: 'reference', operation: 'workspace_read', reviewedCommand: 'cat -- required.md', stdout: reference, stderr: '', evidence: [] } as unknown as ShellEvidence;
    const messages = documentAuthoringContext({ conversation: [], workflow, receipt, craftGuidance: '' });
    expect(size(messages)).toBeGreaterThan(knotAuthorPromptTargetBytes);
    const ledger = JSON.parse(String(messages.find(m => typeof m.content === 'string' && m.content.startsWith('COMPLETE LIVE GUIDANCE'))!.content).split('\n').slice(1).join('\n'));
    expect(ledger.reads[0].payload).toBe(0);
    expect(messages.some(m => typeof m.content === 'string' && m.content.endsWith('\n' + reference))).toBe(true);
    const facts = { authoringBasePromptBytes: size(messages), authoringPromptTargetExceeded: true, authoringElapsedMs: 555000, programBytes: 74000, authoringResponses: 1, authoringBytesPerSecond: 200, turnBudgetMs: 915000 };
    expect(safeKnotActivityDetail({ ...facts, prompt: reference, code: 'private' })).toEqual(facts);
  });
});
