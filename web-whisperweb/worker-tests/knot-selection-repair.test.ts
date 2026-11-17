// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { validatedKnotSelection, validatedKnotDocumentDecision, knotDocumentDecisionFormat, canRepairKnotSelection, safeSelectionFields, validatedKnotSelectionPrefix, knotSelectionDiagnostic, knotSelectionDeadline, knotSelectionAttemptPolicy, knotSelectionPromptSizes, knotSelectionRepairExit, knotSelectionSchemaHash, knotSelectionTokenLimit, knotSelectionRepairPrompt, KnotSelectionRepairLedger } from '../../functions/knot-tool-selection';
import { safeKnotActivityDetail, resolvedKnotSelectionActivity, type KnotActivity } from '../../functions/knot-activity';
import { documentScriptTool, validatedDocumentInvocation } from '../../functions/knot-document-build';
import { documentCompletionBudget, documentReferenceReadAllowed } from '../../functions/knot-document-budget';
import { requestedDocumentFormat } from '../../functions/knot-document-format';
import type { ShellWorkflow } from '../../functions/knot-shell';
import { shellCommandLimit } from '../../functions/knot-work-budget';

const argumentsValue = { stage: 'final', interpreter: 'python3', code: '# synthetic, never executed', path: 'fixture.md', title: '', deliveryLabel: '' };
const decision = (selection: unknown, finish_reason = 'stop') => ({ choices: [{ finish_reason, message: { content: JSON.stringify({ selection }) } }] });
describe('actionable pre-dispatch selection correction', () => {
  it('names repair exits without conflating zero work with zero remaining capacity', () => {
    expect(knotSelectionRepairExit(true, 0, 4, 55000, 0)).toBeUndefined();
    expect(knotSelectionRepairExit(true, 0, 1, 55000, 0)).toBeUndefined();
    expect(knotSelectionRepairExit(true, 0, 0, 55000, 0)).toBe('budget_exhausted');
    expect(knotSelectionRepairExit(true, 0, Math.min(0, 10000), 55000, 0)).toBe('budget_exhausted');
    expect(knotSelectionRepairExit(true, 12, 4, 55000, 0)).toBe('repair_attempts_exhausted');
    expect(knotSelectionRepairExit(true, 0, 4, 55000, 40000)).toBe('deadline_insufficient');
    expect(knotSelectionRepairExit(true, 0, 4, 55000, 39999)).toBeUndefined();
    // Retain the original positive admission predicate's fail-closed NaN behavior.
    for (const document of [false, true]) {
      expect(knotSelectionRepairExit(document, 0, NaN, 55000, 0)).toBe('budget_exhausted');
      expect(knotSelectionRepairExit(document, NaN, 4, 55000, 0)).toBe('repair_attempts_exhausted');
      expect(knotSelectionRepairExit(document, 0, 4, NaN, 0)).toBe('deadline_insufficient');
      expect(knotSelectionRepairExit(document, 0, 4, 55000, NaN)).toBe('deadline_insufficient');
      expect(canRepairKnotSelection(document, 0, NaN, 55000, 0)).toBe(false);
    }
  });
  it('hashes the effective conditional advertised schema, not private generated values', async () => {
    const format = knotDocumentDecisionFormat([documentScriptTool], true);
    const hash = await knotSelectionSchemaHash(format);
    expect(hash).toMatch(/^[a-f0-9]{64}$/);
    expect(await knotSelectionSchemaHash(knotDocumentDecisionFormat([documentScriptTool], true))).toBe(hash);
    expect(await knotSelectionSchemaHash(knotDocumentDecisionFormat([documentScriptTool], false))).not.toBe(hash);
    const changedTool = { ...documentScriptTool, function: { ...documentScriptTool.function, parameters: { ...documentScriptTool.function.parameters, properties: { ...documentScriptTool.function.parameters.properties, stage: { type: 'string', enum: ['source'] } } } } };
    expect(await knotSelectionSchemaHash(knotDocumentDecisionFormat([changedTool], true))).not.toBe(hash);
    expect(safeKnotActivityDetail({ tool: 'document_script', fields: ['arguments.code:required'], attempts: 3, terminationExit: 'repeated_identical_failure', schemaHash: hash, arguments: 'private', providerText: 'private' })).toEqual({ tool: 'document_script', fields: ['arguments.code:required'], attempts: 3, terminationExit: 'repeated_identical_failure', schemaHash: hash });
    expect(safeKnotActivityDetail({ tool: 'private-tool', terminationExit: 'private-exit', schemaHash: 'private-schema' })).toBeUndefined();
    expect(safeKnotActivityDetail(safeKnotActivityDetail({ schemaHash: hash, terminationExit: 'budget_exhausted' }))).toEqual({ schemaHash: hash, terminationExit: 'budget_exhausted' });
  });
  it('attributes invalid arguments only to a known actually advertised tool', () => {
    try { validatedKnotDocumentDecision(decision({ tool: 'document_script', arguments: {} }), [documentScriptTool], new Set(), true); throw new Error('expected rejection'); }
    catch (error) { expect(error).toMatchObject({ tool: 'document_script', fields: expect.arrayContaining(['arguments.code:required']) }); }
    try { validatedKnotDocumentDecision(decision({ tool: 'private-tool', arguments: {} }), [documentScriptTool], new Set(), true); throw new Error('expected rejection'); }
    catch (error) { expect(error).toMatchObject({ message: 'tool_not_advertised' }); expect(JSON.stringify(error)).not.toContain('private-tool'); }
  });
  it('scales full-code deadlines while respecting the absolute turn and terminal reserve', () => {
    expect(knotSelectionDeadline(false, true, false, 285000, 0)).toBe(90000);
    expect(knotSelectionDeadline(false, true, true, 285000, 90000)).toBe(120000);
    expect(knotSelectionDeadline(false, true, true, 55000, 25000)).toBe(25000);
    expect(knotSelectionDeadline(false, false, false, 285000, 0)).toBe(25000);
    expect(knotSelectionDeadline(true, true, true, 285000, 0)).toBe(12000);
    expect(knotSelectionDeadline(false, true, true, 1000, 1000)).toBe(1);
    expect(safeKnotActivityDetail({ deadlineMs: 90000, elapsedMs: 90001, promptBytes: 80000, selectionPhase: 'artifact_authoring', commandDispatched: false, prompt: 'private' })).toEqual({ deadlineMs: 90000, elapsedMs: 90001, promptBytes: 80000, selectionPhase: 'artifact_authoring', commandDispatched: false });
    expect(safeKnotActivityDetail({ deadlineMs: -1, promptBytes: 10000001, selectionPhase: 'private', commandDispatched: true })).toBeUndefined();
  });
  it('measures full serialized UTF-8 sections without clipping evidence at the target', () => {
    const messages = [{ role: 'system', content: 'policy é' }, { role: 'user', content: 'original request 🪢' }, { role: 'assistant', content: null, tool_calls: [{ id: 'owned', function: { name: 'read', arguments: '{}' } }] }, { role: 'tool', content: 'complete live reference ' + 'é'.repeat(17000), tool_call_id: 'owned' }];
    const contract = { schema: 'complete contract' };
    const before = JSON.stringify(messages);
    const result = knotSelectionPromptSizes(messages, contract);
    const bytes = (value: unknown) => new TextEncoder().encode(JSON.stringify(value)).length;
    expect(result).toEqual({ promptBytes: bytes(messages), promptTargetExceeded: true, promptSections: { policyBytes: bytes(messages[0]), requestHistoryBytes: bytes(messages[1]), assistantBytes: bytes(messages[2]), receiptBytes: bytes(messages[3]), framingBytes: 5, contractBytes: bytes(contract) } });
    expect(JSON.stringify(messages)).toBe(before);
    const empty = knotSelectionPromptSizes([], {});
    expect(empty).toMatchObject({ promptBytes: 2, promptTargetExceeded: false, promptSections: { framingBytes: 2 } });
    expect(safeKnotActivityDetail({ ...result, strategy: 'timeout_clock_retry', prompt: 'private', promptSections: { ...result.promptSections, privateKey: 'never retained', negative: -1 } })).toEqual({ ...result, strategy: 'timeout_clock_retry' });
    expect(safeKnotActivityDetail({ strategy: 'private-provider-text', promptSections: { policyBytes: -1, receiptBytes: 10000001, assistantBytes: 'private', framingBytes: 1.5, unknown: 5 } })).toBeUndefined();
    expect(safeKnotActivityDetail(safeKnotActivityDetail(result))).toEqual(result);
  });
  it('distinguishes truncation, field correction and timeout strategy on the same provider', () => {
    expect(knotSelectionAttemptPolicy(false, 0, undefined, 6000)).toEqual({ strategy: 'initial', tokenLimit: 6000 });
    expect(knotSelectionAttemptPolicy(false, 1, 'selection_truncated', 6000)).toEqual({ strategy: 'truncation_escalation', tokenLimit: 9000 });
    expect(knotSelectionAttemptPolicy(false, 2, 'invalid_tool_arguments', 9000)).toEqual({ strategy: 'field_correction', tokenLimit: 9000 });
    expect(knotSelectionAttemptPolicy(false, 3, 'selection_timeout', 12000)).toEqual({ strategy: 'timeout_clock_retry', tokenLimit: 6000 });
    expect(knotSelectionAttemptPolicy(true, 3, 'selection_timeout', 3600)).toEqual({ strategy: 'timeout_clock_retry', tokenLimit: 1800 });
    expect(knotSelectionDeadline(false, true, false, 285000, 0, { promptBytes: 125152, tokenLimit: 6000 })).toBe(120000);
    expect(knotSelectionDeadline(false, true, false, 285000, 0, { promptBytes: 125152, tokenLimit: 9000 })).toBe(140000);
    expect(knotSelectionDeadline(false, true, true, 285000, 0, { promptBytes: 125152, tokenLimit: 6000 })).toBe(150000);
    expect(knotSelectionDeadline(false, true, false, 285000, 0, { promptBytes: 10000000, tokenLimit: 12000 })).toBe(150000);
    expect(knotSelectionDeadline(false, true, true, 285000, 0, { promptBytes: 10000000, tokenLimit: 12000 })).toBe(180000);
    expect(knotSelectionDeadline(false, true, true, 285000, 240000, { promptBytes: 125152, tokenLimit: 6000 })).toBe(40000);
    expect(knotSelectionDeadline(true, true, true, 285000, 0, { promptBytes: 125152, tokenLimit: 12000 })).toBe(12000);
  });
  it.each([
    [{ code: '#'.repeat(64001) }, 'arguments.code:size'],
    [{ code: '\u0000' }, 'arguments.code:control'],
    [{ path: 'fixture@.md' }, 'arguments.path:format'],
    [{ path: 'a'.repeat(162) + '.md' }, 'arguments.path:basenameSize'],
    [{ path: 'other/fixture.md' }, 'arguments.path:directory'],
    [{ path: 'fixture.pdf' }, 'arguments.path:extension'],
    [{ code: ' ' }, 'arguments.code:nonempty'],
    [{ title: 'bad\nlabel' }, 'arguments.title:control'],
    [{ deliveryLabel: 'x'.repeat(49) }, 'arguments.deliveryLabel:size'],
  ])('names exact invocation clause case %# and accepts its corrected next decision', (change, field) => {
    const invalid = { ...argumentsValue, ...change };
    try { validatedKnotDocumentDecision(decision({ tool: 'document_script', arguments: invalid }), [documentScriptTool], new Set(), true); throw new Error('expected rejection'); }
    catch (error) { expect(error).toMatchObject({ message: ['arguments.deliveryLabel:size', 'arguments.code:size'].includes(field) ? 'invalid_tool_arguments' : 'invalid_document_invocation', fields: [field] });
      expect(safeKnotActivityDetail({ fields: [field] })?.fields).toEqual([field]);
      expect(knotSelectionRepairPrompt([field], true)).toContain(JSON.stringify([field])); }
    expect(validatedKnotDocumentDecision(decision({ tool: 'document_script', arguments: argumentsValue }), [documentScriptTool], new Set(), true)).toHaveLength(1);
  });
  it('keeps resident/existing constraints specific and never retains unknown keys or values', () => {
    for (const [value, fields] of [
      [{ ...argumentsValue, stage: 'existing', path: 'fixture.md' }, ['arguments.code:empty']],
      [{ ...argumentsValue, interpreter: 'knot-doc', code: '', path: 'fixture.md' }, ['arguments.stage:residentBuild', 'arguments.path:residentPDF']],
      [{ ...argumentsValue, private_secret: 'never retained' }, ['arguments:additionalProperties']],
      [{ ...argumentsValue, interpreter: 'private-provider' }, ['arguments.interpreter:enum']],
    ] as const) {
      try { validatedDocumentInvocation(value); throw new Error('expected rejection'); }
      catch (error) { expect(error).toMatchObject({ message: 'invalid_document_invocation', fields }); expect(JSON.stringify(error)).not.toMatch(/private_secret|never retained|private-provider/); }
    }
  });
  it('distinguishes unparseable nonempty JSON from an actually empty completion', () => {
    const raw = { choices: [{ finish_reason: 'length', message: { content: '{"selection":{"tool":"document_script","arguments":{"code":"private' } }], usage: { completion_tokens: 6000, prompt_tokens: 100, completion_tokens_details: { reasoning_tokens: 50 }, private_secret: 'never retained' } };
    const detail = safeKnotActivityDetail(knotSelectionDiagnostic(raw, 'openai/gpt-4o'));
    expect(detail).toMatchObject({ argumentBytes: 0, contentBytes: new TextEncoder().encode(raw.choices[0].message.content).length, contentShape: 'partial_json', completionTokens: 6000, promptTokens: 100, reasoningTokens: 50 });
    expect(JSON.stringify(detail)).not.toMatch(/private|never retained/);
    expect(knotSelectionDiagnostic({ choices: [{ message: { content: '' } }] }, 'openai/gpt-4o')).toMatchObject({ contentShape: 'empty', contentBytes: 0 });
    expect(knotSelectionDiagnostic({ choices: [{ message: { content: 'Here is the JSON: {' } }] }, 'openai/gpt-4o')).toMatchObject({ contentShape: 'non_json', contentBytes: 19 });
  });
  it('links terminal repair totals back onto an immutable original rejection, without conflating dispatch and success', () => {
    const id = 'fdf004ad-5db4-4962-aa74-e87a895e5653', selectionIncident = id + ':20';
    const ledger = new KnotSelectionRepairLedger();
    const first = safeKnotActivityDetail(ledger.failed(selectionIncident, 1, 6000));
    ledger.attempted(selectionIncident, 2, 9000);
    ledger.recovered(selectionIncident, 2, 9000);
    const final = safeKnotActivityDetail(ledger.finish('complete')[0]);
    expect(first).toMatchObject({ attempt: 1, attempts: 1, repairAttempts: 0, tokenLimit: 6000, outcome: 'pending' });
    expect(final).toMatchObject({ attempt: 1, attempts: 2, repairAttempts: 1, tokenLimit: 6000, attemptedTokenLimit: 9000, escalatedRetryRan: true, outcome: 'recovered', selectionRecovered: true });
    const rejection: KnotActivity = { id: selectionIncident, requestID: id, sequence: 20, kind: 'tool_selection_retry', label: 'Repairing', recordedAt: '2026-11-12T05:39:00Z', detail: { ...first, fields: ['arguments.code:size'] } };
    const outcome: KnotActivity = { ...rejection, id: id + ':25', sequence: 25, kind: 'tool_selection_outcome', detail: final };
    const resolved = resolvedKnotSelectionActivity([outcome, rejection]);
    expect(resolved[1]).toMatchObject({ label: 'Tool selection recovered; task success not implied', detail: { attempt: 1, attempts: 2, repairAttempts: 1, tokenLimit: 6000, outcome: 'recovered', fields: ['arguments.code:size'] } });
    expect(rejection.detail?.outcome).toBe('pending');
    ledger.attempted(selectionIncident, 3, 6000);
    expect(ledger.finish('degraded')[0]).toMatchObject({ outcome: 'degraded', tokenLimit: 6000, attemptedTokenLimit: 6000, escalatedRetryRan: true });
    expect(ledger.finish('ended')[0]).toMatchObject({ outcome: 'ended', attempts: 3, selectionRecovered: true, escalatedRetryRan: true });
    const failed = new KnotSelectionRepairLedger(); failed.failed(selectionIncident, 1, 6000); failed.attempted(selectionIncident, 2, 9000);
    expect(failed.finish('ended')[0]).toMatchObject({ outcome: 'ended', attempts: 2, repairAttempts: 1, selectionRecovered: false });
    expect(failed.finish('complete')[0].outcome).toBe('degraded');
    const foreign = { ...outcome, requestID: '17ea232f-e013-4660-ba5b-751950bb5cc8' };
    expect(resolvedKnotSelectionActivity([foreign, rejection])[1]).toEqual(rejection);
    expect(safeKnotActivityDetail({ selectionIncident: 'private prompt', contentShape: 'private text', tokenLimit: 999999, completionTokens: -1, reasoning: 'secret' })).toBeUndefined();
  });
  it('advertises source authoring separately from the resident PDF build', () => {
    const format = knotDocumentDecisionFormat([documentScriptTool], true);
    const branches = format.json_schema.schema.properties.selection.anyOf as Record<string, any>[];
    const argumentsSchemas = branches.map(branch => branch.properties?.arguments);
    expect(argumentsSchemas.filter(schema => schema?.properties.stage.enum.includes('source')).every(schema => !schema.properties.interpreter.enum.includes('knot-doc'))).toBe(true);
    const resident = argumentsSchemas.find(schema => schema?.properties.interpreter.enum.includes('knot-doc'));
    expect(resident?.properties.stage.enum).toEqual(['build']);
    expect(resident?.properties.code.enum).toEqual(['']);
    expect(resident?.properties.path.pattern).toBe('\\.pdf$');
  });
  it('rejects genuinely empty zero-usage length responses without calling them token exhaustion', () => {
    const raw = { choices: [{ finish_reason: 'length', message: { content: '' } }], usage: { completion_tokens: 0, prompt_tokens: 0, completion_tokens_details: { reasoning_tokens: 0 } } };
    expect(() => validatedKnotDocumentDecision(raw, [documentScriptTool], new Set(), true)).toThrow('selection_upstream_empty');
    expect(() => validatedKnotSelection(raw, [documentScriptTool], 1, new Set(), true)).toThrow('selection_upstream_empty');
    expect(knotSelectionTokenLimit(false, 2, 'selection_upstream_empty')).toBe(6000);
  });
  it('constructs a unique harness envelope from one complete typed decision', () => {
    const calls = validatedKnotDocumentDecision(decision({ tool: 'document_script', arguments: argumentsValue }), [documentScriptTool], new Set(), true);
    expect(calls).toHaveLength(1); expect(calls[0].id).toMatch(/^decision_[a-f0-9]{32}$/);
    expect(calls[0].type).toBe('function'); expect(JSON.parse(calls[0].function.arguments)).toEqual(argumentsValue);
    expect(knotDocumentDecisionFormat([documentScriptTool], true).json_schema.schema.properties.selection.anyOf).toHaveLength(5);
  });
  it('does not normalize truncated content, model envelopes, unadvertised tools or missing required arguments', () => {
    for (const raw of [decision({ tool: 'document_script', arguments: argumentsValue }, 'length'), decision({ tool: 'other', arguments: argumentsValue }), decision({ tool: 'document_script', arguments: { ...argumentsValue, title: undefined } }), decision([{ tool: 'document_script', arguments: argumentsValue }]), decision({ tool: 'document_script', arguments: argumentsValue, id: 'model-id' })]) {
      expect(() => validatedKnotDocumentDecision(raw, [documentScriptTool], new Set(), true)).toThrow();
    }
    expect(() => validatedKnotDocumentDecision(decision(null), [documentScriptTool], new Set(), true)).toThrow('requested_work_step_required');
    expect(validatedKnotDocumentDecision(decision(null), [documentScriptTool], new Set(), false)).toEqual([]);
  });
  it('allows more than two pre-dispatch document corrections but respects deadline and hard bounds', () => {
    expect(canRepairKnotSelection(true, 2, 6, 100000, 1000)).toBe(true);
    expect(canRepairKnotSelection(true, 11, 6, 100000, 1000)).toBe(true);
    expect(canRepairKnotSelection(true, 12, 6, 100000, 1000)).toBe(false);
    expect(canRepairKnotSelection(true, 0, 6, 100000, 85000)).toBe(false);
    expect(canRepairKnotSelection(true, 0, 0, 100000, 1000)).toBe(false);
    expect(canRepairKnotSelection(false, 2, 6, 100000, 1000)).toBe(false);
  });
  it('retains a valid serial prefix but stops at the first schema-invalid call', () => {
    const call = (id: string, args: unknown) => ({ id, type: 'function', function: { name: 'document_script', arguments: JSON.stringify(args) } });
    const first = call('first', argumentsValue), invalid = call('invalid', { ...argumentsValue, code: undefined }), last = call('last', argumentsValue);
    const raw = { choices: [{ finish_reason: 'tool_calls', message: { tool_calls: [first, invalid, last] } }] };
    const result = validatedKnotSelectionPrefix(raw, [documentScriptTool], 3, new Set(), true);
    expect(result.calls).toEqual([first, invalid, last]);
    expect(result.rejected).toEqual({ index: 1, reason: 'invalid_tool_arguments', fields: ['arguments.code:required'] });
    expect(result.calls.slice(0, result.rejected!.index)).toEqual([first]);
    expect(() => validatedKnotSelectionPrefix(raw, [documentScriptTool], 2, new Set(), true)).toThrow('tool_call_count_invalid');
    expect(() => validatedKnotSelectionPrefix(raw, [documentScriptTool], 3, new Set(['first']), true)).toThrow('tool_envelope_invalid');
    raw.choices[0].message.tool_calls[2] = { ...last, id: 'first' };
    expect(() => validatedKnotSelectionPrefix(raw, [documentScriptTool], 3, new Set(), true)).toThrow('tool_envelope_invalid');
  });
  it('records content-free model/finish/shape/UTF-8 byte facts through the Events allowlist', () => {
    const args = JSON.stringify({ code: 'private 🪢', unknown_secret: 'never retained' });
    const raw = { choices: [{ finish_reason: 'length', message: { tool_calls: [{ function: { arguments: args } }] } }] };
    const detail = safeKnotActivityDetail({ ...knotSelectionDiagnostic(raw, 'openai/gpt-4o'), reason: 'selection_truncated', invalidCall: 1 });
    expect(detail).toEqual({ model: 'openai/gpt-4o', reason: 'selection_truncated', finishReason: 'length', choicesPresent: true, messagePresent: true, toolCallsPresent: true, argumentBytes: new TextEncoder().encode(args).length, contentBytes: 0, contentShape: 'absent', invalidCall: 1 });
    expect(JSON.stringify(detail)).not.toMatch(/private|secret/);
    expect(knotSelectionDiagnostic({ error: { message: 'private provider error' } }, 'openai/gpt-4o')).toMatchObject({ finishReason: 'missing', choicesPresent: false, messagePresent: false, toolCallsPresent: false, argumentBytes: 0 });
    expect(knotSelectionDiagnostic({ choices: [{ finish_reason: 'private text', message: {} }] }, 'openai/gpt-4o').finishReason).toBe('unknown');
    const structured = decision({ tool: 'document_script', arguments: argumentsValue });
    expect(knotSelectionDiagnostic(structured, 'openai/gpt-4o').argumentBytes).toBe(new TextEncoder().encode(JSON.stringify(argumentsValue)).length);
  });
  it('increases a truncated single-operation allowance within a fixed bound, without model migration', () => {
    expect(knotSelectionTokenLimit(false, 0)).toBe(6000);
    expect(knotSelectionTokenLimit(false, 1, 'selection_truncated')).toBe(9000);
    expect(knotSelectionTokenLimit(false, 12, 'selection_truncated')).toBe(12000);
    expect(knotSelectionTokenLimit(true, 12, 'selection_truncated')).toBe(3600);
    expect(knotSelectionTokenLimit(false, 2, 'invalid_tool_arguments')).toBe(6000);
  });
  it('never retains private argument values or unknown property names in diagnostics', () => {
    expect(safeSelectionFields(['arguments.code:required', 'arguments.private_secret:required', 'private-value', 'arguments.data:json'])).toEqual(['arguments.code:required', 'arguments.data:json']);
  });
  it('reserves a full corrective completion without blocking indispensable reference reads', () => {
    const workflow = { documentTask: true, documentPolicy: 'author_v1', documentFormat: requestedDocumentFormat('Create a PDF'), commands: shellCommandLimit - 6, originalRequest: 'Create a PDF' } as ShellWorkflow;
    const budget = documentCompletionBudget(workflow);
    expect(budget).toMatchObject({ remaining: 6, reserved: true, requiredSteps: 3, repairReserve: 3, canReadReference: true, stages: ['source'] });
    expect(documentReferenceReadAllowed(budget, 'workspace_read')).toBe(true);
    expect(documentReferenceReadAllowed(budget, 'skill_read')).toBe(false);
    expect(documentReferenceReadAllowed(documentCompletionBudget({ ...workflow, commands: shellCommandLimit - 3 }), 'workspace_read')).toBe(false);
    const raw = documentCompletionBudget({ ...workflow, documentFormat: requestedDocumentFormat('Create an MD file'), commands: shellCommandLimit - 2 });
    expect(raw).toMatchObject({ remaining: 2, reserved: true, requiredSteps: 1, repairReserve: 1, canReadReference: true, stages: ['final'] });
    expect(documentCompletionBudget({ ...workflow, commands: shellCommandLimit - 7, documentContentFinding: { proposalID: 'owned', issue: 'document_content_incomplete', observations: ['actual gap'] } }).reserved).toBe(true);
  });
  it('names missing document fields instead of discarding them behind a generic reason', () => {
    const raw = { choices: [{ finish_reason: 'tool_calls', message: { tool_calls: [{ id: 'fixture', type: 'function', function: { name: 'document_script', arguments: JSON.stringify({ stage: 'final', interpreter: 'python3', path: 'fixture.md' }) } }] } }] };
    try { validatedKnotSelection(raw, [documentScriptTool], 1, new Set(), true); throw new Error('expected rejection'); }
    catch (error) { expect(error).toMatchObject({ message: 'invalid_tool_arguments', fields: expect.arrayContaining(['arguments.code:required', 'arguments.title:required', 'arguments.deliveryLabel:required']) }); }
  });
  it('distinguishes token truncation from a malformed upstream body and required-step omission', () => {
    expect(() => validatedKnotDocumentDecision(decision(null, 'length'), [documentScriptTool], new Set(), true)).toThrow('selection_truncated');
    expect(() => validatedKnotSelection({ choices: [{ finish_reason: 'length', message: {} }] }, [documentScriptTool], 1, new Set(), true)).toThrow('selection_upstream_empty');
    expect(() => validatedKnotSelection({ error: { message: 'private provider text' } }, [documentScriptTool], 1, new Set(), true)).toThrow('selection_upstream_shape_invalid');
    expect(() => validatedKnotSelection({ choices: [{ finish_reason: 'stop', message: {} }] }, [documentScriptTool], 1, new Set(), true)).toThrow('requested_work_step_required');
  });
  it('names a missing provider message explicitly without logging argument values', () => {
    try { validatedKnotSelection({ choices: [{}] }, [documentScriptTool], 1, new Set(), true); throw new Error('expected rejection'); }
    catch (error) { expect(error).toMatchObject({ message: 'selection_upstream_shape_invalid', fields: ['choices.0.message:required'] }); }
  });
});
