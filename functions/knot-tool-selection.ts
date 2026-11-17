import { validatedKnotAgentActivity, type KnotAgentActivity } from './knot-agent-presentation';
import { validatedSkillDraft } from './knot-skill-drafts';
import { InvalidDocumentInvocation, validatedDocumentInvocation } from './knot-document-build';
import { validatedDocumentPreparation } from './knot-document-program';

import { documentArgumentByteLimit, documentSizeFacts, safeDocumentSizeFacts, type DocumentSizeFacts } from './knot-document-limits';

export type SelectedToolCall = { id: string; type: 'function'; function: { name: string; arguments: string }; activity?: KnotAgentActivity };
/** The provider sees only its function-call envelope and the authored metadata
 * in its advertised argument schema. Execution keeps its stripped arguments.
 * Rejected tails have no normalized activity and retain their original args. */
export function knotProviderToolCalls(calls: SelectedToolCall[]): Omit<SelectedToolCall, 'activity'>[] {
  return calls.map(call => ({ id: call.id, type: 'function', function: {
    name: call.function.name,
    arguments: call.activity ? JSON.stringify({ ...JSON.parse(call.function.arguments), _activity: call.activity }) : call.function.arguments,
  } }));
}
type Schema = Record<string, unknown>;
type Tool = { function: { name: string; parameters: unknown } };
const object = (value: unknown): value is Record<string, unknown> => value !== null && typeof value === 'object' && !Array.isArray(value);
/** Only fixed schema paths/categories, never unknown keys or argument values. */
export function safeSelectionFields(value: unknown): string[] {
  const tokens = new Set(['choices', 'message', 'finish_reason', 'tool_calls', 'id', 'type', 'function', 'name', 'arguments', 'selection', '_activity', 'label', 'purpose', 'tool', 'stage', 'interpreter', 'code', 'path', 'title', 'deliveryLabel', 'authoring', 'data',
    // Browser agent argument names (schema paths only, never values).
    'url', 'text', 'outcome', 'tab_id', 'query', 'selector', 'ref', 'x', 'y', 'key', 'action', 'direction', 'timeout_ms', 'findings', 'sources', 'summary', 'coverage', 'filename', 'kind', 'dy']);
  return Array.isArray(value) ? [...new Set(value.filter((field): field is string => typeof field === 'string' && field.length <= 150 && /:(?:required|type|enum|size|range|additionalProperties|json|unique|complete|control|format|basenameSize|directory|extension|empty|nonempty|residentBuild|residentPDF|sourceOutput)$/.test(field) && field.split(':')[0].split('.').every(token => tokens.has(token) || /^(?:[0-9]|[1-3][0-9]|4[0-7])$/.test(token))))].slice(0, 12) : [];
}
export function safeSelectionTool(value: unknown): string | undefined {
  return typeof value === 'string' && (['session_input', 'document_script', 'document_prepare', 'skill_draft', 'skill_draft_read', 'calculate', 'web_search', 'react'].includes(value) || /^browser_[a-z_]{1,40}$/.test(value)) ? value : undefined;
}
export class KnotSelectionInvalid extends Error {
  readonly fields: string[];
  readonly tool?: string;
  readonly sizeFacts?: DocumentSizeFacts;
  constructor(reason: string, fields: string[] = [], tool?: string, sizeFacts?: DocumentSizeFacts) { super(reason); this.fields = safeSelectionFields(fields); this.tool = safeSelectionTool(tool); this.sizeFacts = safeDocumentSizeFacts(sizeFacts); }
}
/** Hash the actual advertised parameter contract, never generated arguments.
 * Documents pass the exact conditional response_format sent to the provider. */
export async function knotSelectionSchemaHash(contract: unknown): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(contract)));
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('');
}
export const knotSelectionTerminationExits = ['repeated_identical_failure', 'repair_attempts_exhausted', 'deadline_insufficient', 'budget_exhausted', 'timeout_retry_exhausted', 'upstream_empty', 'upstream_shape_invalid', 'size_capacity_exceeded', 'client_capacity_exceeded'] as const;
export type KnotSelectionTerminationExit = typeof knotSelectionTerminationExits[number];

export function knotSelectionDirective<T extends Tool>(tools: T[], requiredName?: string, required = false) {
  if (requiredName) {
    const selected = tools.filter(tool => tool.function.name === requiredName);
    if (selected.length !== 1) throw new KnotSelectionInvalid('tool_not_advertised');
    return { tools: selected, tool_choice: 'required' as const };
  }
  return { tools, tool_choice: required ? 'required' as const : 'auto' as const };
}
/** A document decision contains one typed operation, not provider-authored call
 * IDs/envelopes/batches. Only the harness constructs the execution envelope.
 * The ordinary validator AND the owned actor admission still run afterward. */
export function knotDocumentDecisionFormat(tools: Tool[], required: boolean) {
  // Advertise the same conditional combinations as the invocation validator.
  // Independent enums incorrectly offered knot-doc for source authoring.
  const options: Schema[] = tools.flatMap(tool => documentArgumentVariants(tool).map(parameters => ({ type: 'object', properties: { tool: { type: 'string', enum: [tool.function.name] }, arguments: parameters }, required: ['tool', 'arguments'], additionalProperties: false })));
  if (!required) options.push({ type: 'null' });
  if (!options.length) throw new KnotSelectionInvalid('tool_not_advertised');
  return { type: 'json_schema', json_schema: { name: 'knot_document_decision', strict: true, schema: { type: 'object', properties: { selection: { anyOf: options } }, required: ['selection'], additionalProperties: false } } };
}
function documentArgumentVariants(tool: Tool): unknown[] {
  const schema = tool.function.parameters;
  if (!['document_script', 'document_prepare'].includes(tool.function.name) || !object(schema) || !object(schema.properties)) return [schema];
  const properties = schema.properties;
  const allowed = (key: string, value: string) => object(properties[key]) && Array.isArray(properties[key].enum) && properties[key].enum.includes(value);
  const variants: Schema[] = [];
  for (const stage of ['source', 'build', 'existing', 'final']) {
    if (!allowed('stage', stage)) continue;
    const authored = ['python3', 'bash'].filter(interpreter => allowed('interpreter', interpreter));
    const branch = (interpreters: string[], resident = false) => {
      if (!interpreters.length) return;
      variants.push({ ...schema, properties: { ...properties,
        stage: { type: 'string', enum: [stage] }, interpreter: { type: 'string', enum: interpreters },
        ...(tool.function.name === 'document_prepare' ? { authoring: { type: 'string', enum: resident || stage === 'existing' ? ['measure'] : stage === 'source' ? ['author', 'measure'] : ['author'] } } : { code: { ...(object(properties.code) ? properties.code : {}), ...(resident || stage === 'existing' ? { enum: [''] } : ['build', 'final'].includes(stage) ? { minLength: 1 } : {}) } }),
        path: { ...(object(properties.path) ? properties.path : {}), pattern: resident ? '\\.pdf$' : stage === 'source' ? '\\.(?:[mM][dD]|[hH][tT][mM][lL])$' : stage === 'final' ? '\\.(?:txt|md|html|csv|json)$' : stage === 'existing' ? '\\.(?:[pP][dD][fF]|[dD][oO][cC][xX]|[xX][lL][sS][xX]|[pP][pP][tT][xX]|[tT][xX][tT]|[mM][dD]|[hH][tT][mM][lL]|[cC][sS][vV]|[jJ][sS][oO][nN])$' : '\\.(?:[pP][dD][fF]|[dD][oO][cC][xX]|[xX][lL][sS][xX]|[pP][pP][tT][xX])$' },
      } });
    };
    branch(authored);
    if (stage === 'build' && allowed('interpreter', 'knot-doc')) branch(['knot-doc'], true);
  }
  if (!variants.length) throw new KnotSelectionInvalid('tool_not_advertised');
  return variants;
}
/** A length flag with no generated bytes or positive reported usage is not
 * evidence that a larger output budget will help. Never re-ask this condition. */
function incompleteLength(raw: unknown): KnotSelectionInvalid {
  const diagnostic = knotSelectionDiagnostic(raw, '');
  const choice = object(raw) && Array.isArray(raw.choices) ? raw.choices[0] : undefined;
  const calls = object(choice) && object(choice.message) ? choice.message.tool_calls : undefined;
  const empty = diagnostic.contentBytes === 0 && diagnostic.argumentBytes === 0 && !(Array.isArray(calls) && calls.length) && !(diagnostic.completionTokens && diagnostic.completionTokens > 0) && !(diagnostic.reasoningTokens && diagnostic.reasoningTokens > 0);
  return new KnotSelectionInvalid(empty ? 'selection_upstream_empty' : 'selection_truncated', ['choices.0.finish_reason:complete']);
}
export function validatedKnotDocumentDecision(raw: unknown, tools: Tool[], usedIDs: Set<string>, required: boolean): SelectedToolCall[] {
  const choice = object(raw) && Array.isArray(raw.choices) ? raw.choices[0] : undefined;
  if (!object(choice) || !object(choice.message)) throw new KnotSelectionInvalid('selection_upstream_shape_invalid', ['choices.0.message:required']);
  if (choice.finish_reason === 'length') throw incompleteLength(raw);
  if (choice.finish_reason !== 'stop') throw new KnotSelectionInvalid('tool_finish_reason_invalid', ['choices.0.finish_reason:complete']);
  let decision: unknown;
  try { decision = JSON.parse(typeof choice.message.content === 'string' ? choice.message.content : ''); }
  catch { throw new KnotSelectionInvalid('incomplete_tool_selection', ['selection:json']); }
  if (!object(decision) || !Object.hasOwn(decision, 'selection')) throw new KnotSelectionInvalid('incomplete_tool_selection', ['selection:required']);
  if (Object.keys(decision).some(key => key !== 'selection')) throw new KnotSelectionInvalid('tool_envelope_invalid', ['selection:additionalProperties']);
  if (decision.selection === null) {
    if (required) throw new KnotSelectionInvalid('requested_work_step_required', ['selection:required']);
    return [];
  }
  const selection = decision.selection;
  const knownTool = object(selection) && tools.some(tool => tool.function.name === selection.tool) ? safeSelectionTool(selection.tool) : undefined;
  if (!object(selection) || typeof selection.tool !== 'string' || !Object.hasOwn(selection, 'arguments') || Object.keys(selection).some(key => !['tool', 'arguments'].includes(key))) throw new KnotSelectionInvalid('tool_envelope_invalid', ['selection:type'], knownTool);
  const id = 'decision_' + crypto.randomUUID().replaceAll('-', '');
  return validatedKnotSelection({ choices: [{ finish_reason: 'tool_calls', message: { tool_calls: [{ id, type: 'function', function: { name: selection.tool, arguments: JSON.stringify(selection.arguments) } }] } }] }, tools, 1, usedIDs, required);
}
/** Authoring returns complete code, so its non-streamed response needs more
 * than an ordinary tool choice. Reserve time for terminal Events/Stop and never
 * extend the absolute owned turn. A timeout permits ONE fresh pre-dispatch retry. */
export function knotSelectionDeadline(browser: boolean, authoring: boolean, timedOut: boolean, expiresAt: number, now: number, size?: { promptBytes: number; tokenLimit: number }): number {
  // This is still a bounded monolithic call, not streaming progress. Larger
  // complete input/output gets more clock, never a longer absolute owned turn.
  const promptBytes = Number.isSafeInteger(size?.promptBytes) && size!.promptBytes > 0 ? size!.promptBytes : 0;
  const tokens = Number.isSafeInteger(size?.tokenLimit) && size!.tokenLimit > 0 ? size!.tokenLimit : 6000;
  const extra = Math.ceil(Math.max(0, promptBytes - 32768) / 32768) * 10000 + Math.ceil(Math.max(0, tokens - 6000) / 3000) * 20000;
  const allowance = browser ? 12000 : authoring ? Math.min(timedOut ? 180000 : 150000, (timedOut ? 120000 : 90000) + extra) : timedOut ? 40000 : 25000;
  // File preparation shares the owned task lifetime, not an unrelated 90/150s
  // stopwatch. Ordinary chat/browser selection retains its existing policy.
  return Math.max(1, authoring && !browser ? expiresAt - now - 5000 : Math.min(allowance, expiresAt - now - 5000));
}

export const knotSelectionStrategies = ['initial', 'truncation_escalation', 'field_correction', 'timeout_clock_retry', 'minimal_menu_retry'] as const;
export type KnotSelectionStrategy = typeof knotSelectionStrategies[number];
export function knotSelectionAttemptPolicy(browser: boolean, attempt: number, reason: string | undefined, previous: number): { strategy: KnotSelectionStrategy; tokenLimit: number } {
  const base = knotSelectionTokenLimit(browser, 0);
  // A timeout is NOT evidence of output truncation. Reset even a previously
  // escalated attempt, then spend the bounded longer clock on the same provider.
  if (reason === 'selection_timeout') return { strategy: 'timeout_clock_retry', tokenLimit: base };
  if (reason === 'selection_truncated') return { strategy: 'truncation_escalation', tokenLimit: Math.max(previous, knotSelectionTokenLimit(browser, attempt, reason)) };
  return { strategy: reason ? 'field_correction' : 'initial', tokenLimit: Math.max(base, previous) };
}
/** Same advertised argument contracts, smaller choice set. This prepares a
 * fresh pre-dispatch choice only; actor admission and read gates still apply. */
export function knotMinimalSelectionTools<T extends Tool>(tools: T[]): T[] {
  return tools.filter(tool => ['session_input', 'document_prepare', 'document_script'].includes(tool.function.name));
}
// Optimization target only; complete live guides and owned recovery evidence
// legitimately exceed it. Keep a separate actual transport safety envelope.
export const knotSelectionPromptByteLimit = 32768;
export const knotSelectionTransportByteLimit = 524288;
export const knotPromptSectionKeys = ['policyBytes', 'requestHistoryBytes', 'receiptBytes', 'assistantBytes', 'framingBytes', 'contractBytes'] as const;
export type KnotPromptSections = Partial<Record<typeof knotPromptSectionKeys[number], number>>;
/** Exact UTF-8 serialized message sections, not excerpts, token estimates or
 * raw text. Nested receipts include their complete live/reference evidence.
 * Contract bytes are separate; the other sections sum to promptBytes exactly. */
export function knotSelectionPromptSizes(messages: readonly { role: string }[], contract: unknown) {
  const bytes = (value: unknown) => new TextEncoder().encode(JSON.stringify(value)).length;
  const promptSections = { policyBytes: 0, requestHistoryBytes: 0, receiptBytes: 0, assistantBytes: 0, framingBytes: 2 + Math.max(0, messages.length - 1), contractBytes: bytes(contract) };
  for (const message of messages) {
    const key = message.role === 'system' ? 'policyBytes' : message.role === 'tool' ? 'receiptBytes' : message.role === 'assistant' ? 'assistantBytes' : 'requestHistoryBytes';
    promptSections[key] += bytes(message);
  }
  const promptBytes = bytes(messages);
  return { promptBytes, promptSections, promptTargetExceeded: promptBytes > knotSelectionPromptByteLimit };
}

/** Malformed PRE-dispatch choices can be corrected, never dispatched commands.
 * The same absolute turn deadline, cancellation and hard shell budget apply. */
export function canRepairKnotSelection(document: boolean, attempts: number, remaining: number, deadline: number, now: number): boolean {
  return knotSelectionRepairExit(document, attempts, remaining, deadline, now) === undefined;
}
/** Same gate as admission, with an explicit, fixed terminal category. Attempts
 * count completed repairs: twelve document repairs permit thirteen selections. */
export function knotSelectionRepairExit(document: boolean, attempts: number, remaining: number, deadline: number, now: number): KnotSelectionTerminationExit | undefined {
  if (!(remaining > 0)) return 'budget_exhausted';
  if (!(attempts < (document ? 12 : 2))) return 'repair_attempts_exhausted';
  if (!(now < deadline - (document ? 15000 : 14000))) return 'deadline_insufficient';
}
function schemaFields(value: unknown, schema: Schema, path = 'arguments', depth = 0): string[] {
  if (depth > 12) return [path + ':size'];
  if (Array.isArray(schema.enum) && !schema.enum.includes(value)) return [path + ':enum'];
  const types = Array.isArray(schema.type) ? schema.type : [schema.type];
  if (schema.type !== undefined && !types.some(type => type === 'null' ? value === null : type === 'object' ? object(value) : type === 'array' ? Array.isArray(value) : type === 'integer' ? typeof value === 'number' && Number.isSafeInteger(value) : type === 'number' ? typeof value === 'number' && Number.isFinite(value) : typeof value === type)) return [path + ':type'];
  const fields: string[] = [];
  if (object(value)) {
    const properties = object(schema.properties) ? schema.properties : {};
    if (Array.isArray(schema.required)) for (const key of schema.required) if (typeof key === 'string' && !Object.hasOwn(value, key)) fields.push(path + '.' + key + ':required');
    if (schema.additionalProperties === false && Object.keys(value).some(key => !Object.hasOwn(properties, key))) fields.push(path + ':additionalProperties');
    for (const [key, child] of Object.entries(value)) if (object(properties[key])) fields.push(...schemaFields(child, properties[key], path + '.' + key, depth + 1));
  }
  if (Array.isArray(value) && object(schema.items)) for (let index = 0; index < value.length; index++) fields.push(...schemaFields(value[index], schema.items, path + '.' + index, depth + 1));
  if (typeof value === 'string' && ((typeof schema.maxLength === 'number' && (path === 'arguments.code' ? Array.from(value).length : value.length) > schema.maxLength) || (typeof schema.minLength === 'number' && value.length < schema.minLength))) fields.push(path + ':size');
  if (typeof value === 'number' && ((typeof schema.minimum === 'number' && value < schema.minimum) || (typeof schema.maximum === 'number' && value > schema.maximum))) fields.push(path + ':range');
  return fields;
}
function selectionCalls(raw: unknown, remaining: number, required: boolean): unknown[] {
  const choice = object(raw) && Array.isArray(raw.choices) ? raw.choices[0] : undefined;
  if (!object(choice) || !object(choice.message)) throw new KnotSelectionInvalid('selection_upstream_shape_invalid', ['choices.0.message:required']);
  if (choice.finish_reason === 'length') throw incompleteLength(raw);
  const calls = choice.message.tool_calls;
  if (calls == null || Array.isArray(calls) && calls.length === 0) {
    if (choice.finish_reason !== 'stop') throw new KnotSelectionInvalid('incomplete_tool_selection', ['choices.0.finish_reason:complete']);
    if (required) throw new KnotSelectionInvalid('requested_work_step_required', ['choices.0.message.tool_calls:required']);
    return [];
  }
  if (choice.finish_reason !== 'tool_calls') throw new KnotSelectionInvalid('tool_finish_reason_invalid', ['choices.0.finish_reason:complete']);
  if (!Array.isArray(calls) || calls.length > remaining || calls.length > 48) throw new KnotSelectionInvalid('tool_call_count_invalid', ['choices.0.message.tool_calls:size']);
  return calls;
}
function validatedEnvelopes(calls: unknown[], usedIDs: Set<string>): asserts calls is SelectedToolCall[] {
  const ids = new Set<string>();
  for (const call of calls) {
    if (!object(call) || call.type !== 'function' || typeof call.id !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(call.id) || ids.has(call.id) || usedIDs.has(call.id) || !object(call.function) || typeof call.function.name !== 'string' || typeof call.function.arguments !== 'string') throw new KnotSelectionInvalid('tool_envelope_invalid', ['choices.0.message.tool_calls:type']);
    ids.add(call.id);
  }
}
export function validatedKnotSelection(raw: unknown, tools: Tool[], remaining: number, usedIDs: Set<string>, required = false): SelectedToolCall[] {
  const calls = selectionCalls(raw, remaining, required);
  validatedEnvelopes(calls, usedIDs);
  const normalized: SelectedToolCall[] = [];
  for (const call of calls) {
    const selectedName = call.function.name, encodedArguments = call.function.arguments;
    const advertised = tools.find(tool => tool.function.name === selectedName);
    if (!advertised) throw new KnotSelectionInvalid('tool_not_advertised', ['selection.tool:enum']);
    let sizeFacts: DocumentSizeFacts | undefined;
    const invalid = (reason: string, fields: string[] = []) => new KnotSelectionInvalid(reason, fields, advertised.function.name, fields.some(field => field.endsWith(':size')) ? sizeFacts : undefined);
    const argumentBytes = new TextEncoder().encode(encodedArguments).length;
    if (selectedName !== 'document_script' && encodedArguments.length > 74000) throw invalid('tool_arguments_too_large', ['arguments:size']);
    // Parse only a bounded envelope, then measure the actual decoded program.
    if (selectedName === 'document_script' && argumentBytes > 200000) throw new KnotSelectionInvalid('tool_arguments_too_large', ['arguments:size'], selectedName, { argumentBytes, argumentByteLimit: documentArgumentByteLimit });
    let args: unknown;
    try { args = JSON.parse(encodedArguments); } catch { throw invalid('invalid_tool_arguments', ['arguments:json']); }
    if (selectedName === 'document_script') {
      sizeFacts = documentSizeFacts(args, encodedArguments);
      if (argumentBytes > documentArgumentByteLimit) throw invalid('tool_arguments_too_large', ['arguments:size']);
    }
    if (!object(args) || !object(advertised.function.parameters)) throw invalid('invalid_tool_arguments', ['arguments:type']);
    const fields = schemaFields(args, advertised.function.parameters);
    if (fields.length) throw invalid('invalid_tool_arguments', fields);
    let activity: KnotAgentActivity | undefined;
    if (object(advertised.function.parameters.properties) && Object.hasOwn(advertised.function.parameters.properties, '_activity')) {
      activity = validatedKnotAgentActivity(args._activity);
      if (!activity) throw invalid('invalid_tool_arguments', ['arguments._activity:type']);
      const { _activity: ignored, ...execution } = args;
      args = execution;
    }
    // Presentation is removed before every execution-specific validator.
    normalized.push({ id: call.id, type: 'function', function: { name: selectedName, arguments: JSON.stringify(args) }, ...(activity ? { activity } : {}) });
    if (selectedName === 'document_script') {
      try { validatedDocumentInvocation(args); } catch (error) { throw new KnotSelectionInvalid('invalid_document_invocation', error instanceof InvalidDocumentInvocation ? error.fields : ['arguments:complete'], selectedName, error instanceof InvalidDocumentInvocation ? error.sizeFacts : undefined); }
    }
    if (selectedName === 'document_prepare') {
      try { validatedDocumentPreparation(args); } catch (error) { throw new KnotSelectionInvalid('invalid_document_invocation', error instanceof InvalidDocumentInvocation ? error.fields : ['arguments:complete'], selectedName); }
    }
    if (selectedName === 'skill_draft') {
      try { validatedSkillDraft(args); } catch { throw invalid('invalid_skill_draft'); }
    }
    if (selectedName === 'session_input' && (!object(args) || typeof args.data !== 'string' || !args.data.trim() || new TextEncoder().encode(args.data.trim()).length > 12000 || args.data.includes('\u0000'))) throw invalid('invalid_command_size_or_text', ['arguments.data:size']);
  }
  return normalized;
}

export type KnotSelectionTail = { index: number; reason: string; fields: string[] };
/** Only a coherent, bounded provider envelope may enter serial dispatch. A
 * schema-invalid tail does not erase a valid prefix, but nothing at/after that
 * position may execute. Ambiguous IDs, truncation and envelope errors fail closed. */
export function validatedKnotSelectionPrefix(raw: unknown, tools: Tool[], remaining: number, usedIDs: Set<string>, required = false): { calls: SelectedToolCall[]; rejected?: KnotSelectionTail } {
  const calls = selectionCalls(raw, remaining, required);
  validatedEnvelopes(calls, usedIDs);
  const normalized: SelectedToolCall[] = [];
  for (let index = 0; index < calls.length; index++) {
    try { normalized.push(...validatedKnotSelection({ choices: [{ finish_reason: 'tool_calls', message: { tool_calls: [calls[index]] } }] }, tools, 1, usedIDs, true)); }
    catch (error) {
      if (!(error instanceof KnotSelectionInvalid) || index === 0) throw error;
      return { calls: [...normalized, ...calls.slice(index)], rejected: { index, reason: error.message, fields: error.fields } };
    }
  }
  return { calls: normalized };
}
/** Content-free facts, not provider text or argument values. Unknown finish
 * reasons are categorized, not copied into diagnostics. */
export function knotSelectionDiagnostic(raw: unknown, model: string) {
  const choicesPresent = object(raw) && Array.isArray(raw.choices);
  const choice = object(raw) && Array.isArray(raw.choices) ? raw.choices[0] : undefined;
  const messagePresent = object(choice) && object(choice.message);
  const message = messagePresent ? choice.message as Record<string, unknown> : undefined;
  const toolCallsPresent = Array.isArray(message?.tool_calls);
  let argumentBytes = 0;
  if (toolCallsPresent) for (const call of message!.tool_calls as unknown[]) {
    if (object(call) && object(call.function) && typeof call.function.arguments === 'string') argumentBytes += new TextEncoder().encode(call.function.arguments).length;
  }
  else if (typeof message?.content === 'string') {
    try {
      const parsed: unknown = JSON.parse(message.content);
      if (object(parsed) && object(parsed.selection) && Object.hasOwn(parsed.selection, 'arguments')) argumentBytes = new TextEncoder().encode(JSON.stringify(parsed.selection.arguments)).length;
    } catch { /* Incomplete JSON is not parsed or logged. */ }
  }
  const content = typeof message?.content === 'string' ? message.content : undefined;
  const contentBytes = content === undefined ? 0 : new TextEncoder().encode(content).length;
  let contentShape: 'absent' | 'empty' | 'json' | 'partial_json' | 'non_json' = content === undefined ? 'absent' : !content.trim() ? 'empty' : 'non_json';
  if (content?.trim()) {
    try { JSON.parse(content); contentShape = 'json'; }
    catch { if (/^[{[]/.test(content.trimStart())) contentShape = 'partial_json'; }
  }
  const usage = object(raw) && object(raw.usage) ? raw.usage : undefined;
  const completionDetails = object(usage?.completion_tokens_details) ? usage.completion_tokens_details : undefined;
  const counts: { completionTokens?: number; promptTokens?: number; reasoningTokens?: number } = {};
  for (const [key, value] of [['completionTokens', usage?.completion_tokens], ['promptTokens', usage?.prompt_tokens], ['reasoningTokens', completionDetails?.reasoning_tokens]] as const) if (Number.isSafeInteger(value) && (value as number) >= 0 && (value as number) <= 10000000) counts[key] = value as number;
  const finish = object(choice) ? choice.finish_reason : undefined;
  const finishReason = typeof finish !== 'string' ? 'missing' : ['stop', 'tool_calls', 'length', 'content_filter', 'function_call', 'error'].includes(finish) ? finish : 'unknown';
  return { model, finishReason, choicesPresent, messagePresent, toolCallsPresent, argumentBytes: Math.min(1000000, argumentBytes), contentBytes: Math.min(1000000, contentBytes), contentShape, ...counts };
}
export function knotSelectionRepairPrompt(fields: string[], document: boolean): string {
  return 'Trusted field corrections (paths/categories only; no argument values): ' + JSON.stringify(safeSelectionFields(fields)) + '. ' + (document ? 'Return ONE complete schema-valid selection object, beginning with { and ending with }. No text outside JSON, preamble, Markdown, reasoning, model-authored envelope/ID or sibling call. The last decision did not dispatch or consume a shell command. Keep earlier owned receipts and complete content intact. Clause meanings: code:size is at most 64000 Unicode code points, with complete encoded arguments bounded to 74000 UTF-8 bytes including escaping; no sliced-authoring operation is available and required content must not be cut to fit; control forbids NUL in code and control characters in labels; path:format requires a safe relative path; basenameSize is at most 164 characters; directory permits nested authored output only under deliverables/; extension must match stage; empty requires empty code; nonempty requires nonblank code; residentBuild requires stage=build; residentPDF requires lowercase .pdf; code:sourceOutput means the source program wrote the Office deliverable itself: stage=source code must write ONLY the complete Markdown/HTML source to the declared .md/.html path, with no python-docx/openpyxl/python-pptx/reportlab imports and no .docx/.xlsx/.pptx output (the later build stage converts the measured source). Source authoring uses stage=source and interpreter=python3 or bash with complete author code. knot-doc is ONLY stage=build, code="", lowercase .pdf AFTER an actual measured, approved source receipt; never skip source authoring to satisfy the resident clauses.' : '');
}
export type KnotSelectionIncident = { selectionIncident: string; attempt: number; attempts: number; repairAttempts: number; tokenLimit: number; attemptedTokenLimit: number; escalatedRetryRan: boolean; selectionRecovered: boolean; outcome: 'pending' | 'recovered' | 'degraded' | 'ended' };
/** Bounded pre-dispatch incidents only. A corrected selection is never proof of
 * executed work; terminal outcome records the surrounding response separately. */
export class KnotSelectionRepairLedger {
  private incidents = new Map<string, KnotSelectionIncident>();
  failed(id: string, attempt: number, tokenLimit: number): KnotSelectionIncident {
    const previous = this.incidents.get(id);
    const state: KnotSelectionIncident = previous ?? { selectionIncident: id, attempt, attempts: attempt, repairAttempts: attempt - 1, tokenLimit, attemptedTokenLimit: tokenLimit, escalatedRetryRan: false, selectionRecovered: false, outcome: 'pending' };
    this.incidents.set(id, state);
    this.attempted(id, attempt, tokenLimit);
    return { ...state };
  }
  attempted(id: string | undefined, attempt: number, tokenLimit: number): void {
    const state = id ? this.incidents.get(id) : undefined;
    if (state) Object.assign(state, { attempts: Math.max(state.attempts, attempt), repairAttempts: Math.max(state.repairAttempts, attempt - 1), attemptedTokenLimit: tokenLimit, escalatedRetryRan: state.escalatedRetryRan || attempt > state.attempt && tokenLimit > state.tokenLimit });
  }
  recovered(id: string | undefined, attempt: number, tokenLimit: number): void {
    const state = id ? this.incidents.get(id) : undefined;
    this.attempted(id, attempt, tokenLimit);
    if (state) state.selectionRecovered = true;
  }
  finish(terminal: 'complete' | 'degraded' | 'ended'): KnotSelectionIncident[] {
    return [...this.incidents.values()].map(state => ({ ...state, outcome: terminal === 'ended' ? 'ended' : terminal === 'complete' && state.selectionRecovered ? 'recovered' : 'degraded' }));
  }
}
export function knotSelectionTokenLimit(browser: boolean, attempt: number, reason?: string): number {
  const base = browser ? 1800 : 6000;
  return reason === 'selection_truncated' ? Math.min(browser ? 3600 : 12000, base + (browser ? 900 : 3000) * Math.min(2, attempt)) : base;
}
