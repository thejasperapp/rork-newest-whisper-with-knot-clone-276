import { safeDocumentDiagnostic } from './knot-document-diagnostics';
import { safeDocumentSizeFacts, type DocumentSizeFacts } from './knot-document-limits';
import type { KnotAuthorTransportVitals } from './knot-author-streaming';
import type { KnotModelTransportFacts } from './knot-model-transport';
import type { KnotBot } from './knot-agent';
import { shellCommandLimit } from './knot-work-budget';
import { safeSelectionFields, safeSelectionTool, knotSelectionTerminationExits, knotSelectionStrategies, knotPromptSectionKeys, type KnotPromptSections, type KnotSelectionStrategy, type KnotSelectionTerminationExit } from './knot-tool-selection';
import { knotTaskModels } from './knot-task-experience';
import { documentProgramChecks, documentProgramSliceCharacters, documentProgramSliceBytes, type DocumentProgramDetail } from './knot-document-program';
import { knotCreationSizeClasses, type KnotCreationSizeClass } from './knot-turn-economics';

/** Server-owned, content-free observations. Never accepts model reasoning or text. */
export const knotActivityLabels: Record<string, string> = {
  activity_open: 'Operation opened', activity_close: 'Operation ended', activity_result: 'Operation result described',
  skill_read_started: 'Reading live communication guidance', skill_read_complete: 'Live communication guidance read',
  reaction_guide_cached: 'Using session-cached reaction guidance',
  reaction_guide_default: 'Using default reaction guidance; no placement claimed yet',
  reaction_unavailable: 'Reaction not confirmed; no reaction claimed', reaction_unsupported: 'This client cannot display live reactions',
  conversation_memory_started: 'Reading saved workspace memory for this question',
  conversation_memory_complete: 'Current workspace memory read confirmed',
  conversation_memory_unavailable: 'Current workspace memory read not confirmed',
  background_started: 'Server took ownership; work continues without the app',
  background_completed: 'Result saved to the originating chat',
  background_degraded: 'Best verified result saved; requested work remains incomplete',
  background_stopped: 'Server task stopped; inspect execution receipts for termination',
  background_push_unconfirmed: 'Chat result saved; completion notification unconfirmed',
  accepted: 'Request received', connection_check_started: 'Checking workspace connection',
  connection_verified: 'Workspace connection verified', work_routing: 'Choosing tools',
  search_requested: 'Requesting web sources', search_complete: 'Web sources returned',
  search_unavailable: 'Web sources unavailable', calculation_started: 'Calculating',
  calculation_complete: 'Calculation returned', tool_unavailable: 'Tool unavailable',
  model_transport_attempt: 'Model transport request started; no command dispatched',
  model_transport_retry: 'Retrying model transport; no command dispatched',
  model_transport_outcome: 'Model transport outcome recorded; task success not implied',
  classification_returned: 'Classification response observed; no command dispatched',
  selection_returned: 'Selection response observed; no command dispatched',
  tool_selection_attempt: 'Selection request started; no command dispatched',
  tool_selection_retry: 'Repairing tool selection; nothing dispatched',
  tool_selection_partial: 'Valid prefix selected; invalid tail will not execute',
  tool_selection_rejected: 'Tool selection rejected; nothing dispatched',
  tool_selection_unavailable: 'Tool selection service unavailable',
  tool_selection_outcome: 'Selection repair outcome recorded',
  tool_request_rejected: 'Tool request rejected before execution',
  shell_review_ready: 'Workspace command prepared', generating: 'Reply connection opened',
  finalizing: 'Formatting reply', complete: 'Response prepared', error: 'Response unavailable',
  rejected: 'Response not completed', cancelled: 'Response cancelled; remote work may still be active',
  browser_read_started: 'Reading browser', browser_read_complete: 'Browser observation returned',
  browser_read_unavailable: 'Browser observation unavailable',
  browser_start_intent: 'Browser start requested', browser_start_complete: 'Browser start confirmed',
  browser_navigate_intent: 'Browser navigation requested', browser_navigate_complete: 'Browser navigation acknowledged',
  browser_input_intent: 'Browser input requested', browser_input_complete: 'Browser input acknowledged',
  browser_stop_intent: 'Browser stop requested', browser_stop_complete: 'Browser stop confirmed',
  browser_action_uncertain: 'Browser action not confirmed',
  browser_tab_open_intent: 'New browser tab requested', browser_tab_open_complete: 'Browser tab opened',
  browser_tab_activate_intent: 'Browser tab switch requested', browser_tab_activate_complete: 'Browser tab switched',
  browser_tab_close_intent: 'Browser tab close requested', browser_tab_close_complete: 'Browser tab closed',
  browser_back_intent: 'Browser back requested', browser_back_complete: 'Browser moved back',
  browser_forward_intent: 'Browser forward requested', browser_forward_complete: 'Browser moved forward',
  browser_find_intent: 'Page search requested', browser_find_complete: 'Page search returned',
  browser_wait_intent: 'Waiting for the page', browser_wait_complete: 'Page wait finished',
  browser_download_intent: 'Download requested', browser_download_complete: 'Download saved to the workspace',
  browser_upload_intent: 'Upload requested', browser_upload_complete: 'Upload acknowledged',
  document_content_started: 'Comparing document content with the request and sources',
  document_content_complete: 'Complete-text AI comparison passed; file captured',
  document_content_unconfirmed: 'File captured; content quality verdict unconfirmed, not a pass',
  document_content_unavailable: 'Document content not confirmed; file not delivered',
  document_proof_started: 'Preparing final-file render, text and format checks',
  document_proof_complete: 'Final-file mechanical checks passed; file captured',
  document_proof_unavailable: 'Final-file proof incomplete; document not delivered',
  turn_economics: 'Creation budget calibrated to measured authoring throughput',
  document_program_attempt: 'Authoring the next uncommitted slice; nothing executed',
  document_program_retry: 'Repairing the same uncommitted slice; accepted prefix unchanged',
  document_program_started: 'Bounded document authoring opened; nothing executed',
  document_program_slice: 'Immutable document program slice recorded; nothing executed',
  document_program_sealed: 'Complete document program sealed; not yet executed',
  document_work_unavailable: 'Document work stopped before delivery',
  document_review_started: 'Capturing document and reviewing rendered pages',
  document_review_complete: 'File captured; visual AI review passed',
  document_review_unavailable: 'File captured; optional visual review incomplete',
  document_quality_qualified: 'File captured with checked quality shortfalls; not a quality pass',
  document_visual_incomplete: 'All-page visual review not passed; file not delivered',
};
/** Fixed command-admission categories only; never commands, paths or output. */
export const knotShellAdmissionReasons = [
  'communication_read_not_task_step', 'conversation_memory_read_only', 'memory_write_before_work', 'memory_write_deferred', 'relevant_skill_read_required', 'skill_creation_read_required', 'skill_draft_after_work_required', 'skill_draft_already_written', 'invalid_skill_draft', 'workflow_command_limit_reached',
  'document_output_format_ambiguous', 'document_output_format_unsupported', 'document_output_format_mismatch', 'document_execution_required', 'document_final_already_recorded',
  'document_completion_steps_reserved', 'document_completion_budget_insufficient', 'document_next_step_not_prepared', 'optional_skill_draft_read_failed', 'skill_draft_not_in_catalog',
  'memory_read_first', 'live_index_first', 'skill_index_not_allowed', 'skill_index_already_completed',
  'skill_read_not_allowed', 'skill_read_limit_reached', 'skill_read_already_completed', 'document_skill_read_required',
  'memory_read_already_completed', 'memory_write_already_completed', 'workspace_inventory_not_allowed',
  'workspace_inventory_already_completed', 'recovery_read_not_authorized', 'workspace_inventory_required',
  'skill_reference_requires_read_command', 'invalid_document_invocation', 'document_source_required',
  'document_authoring_timeout', 'document_program_invalid', 'document_program_owner_mismatch', 'document_program_closed', 'document_program_sequence_mismatch', 'document_program_capacity_exceeded', 'document_program_changed',
  'size_capacity_exceeded', 'client_capacity_exceeded', 'document_structured_invocation_required', 'document_source_read_required', 'document_authoring_required', 'document_build_already_recorded',
] as const;
const activityReasons = new Set<string>([...knotShellAdmissionReasons, 'document_content_incomplete', 'document_content_unavailable', 'document_content_evidence_too_large', 'document_content_source_required', 'document_visual_incomplete', 'document_visual_review_unavailable', 'document_visual_quality_shortfalls', 'document_proof_coverage_incomplete', 'document_review_choice_required', 'document_bytes_changed', 'document_literal_markup_detected', 'document_memory_protocol_required', 'document_conversion_required', 'document_proof_required', 'document_skill_read_required', 'upstream_quota_exhausted', 'upstream_rate_limited', 'selection_timeout', 'selection_prompt_too_large', 'selection_deadline_insufficient', 'selection_upstream_shape_invalid', 'selection_upstream_empty', 'selection_truncated', 'selection_response_too_large', 'requested_work_step_required', 'tool_finish_reason_invalid', 'tool_call_count_invalid', 'tool_envelope_invalid', 'tool_not_advertised', 'tool_arguments_too_large', 'incomplete_tool_selection', 'shell_active_capacity', 'shell_history_capacity', 'shell_active_context_conflict', 'shell_capacity_or_context', 'invalid_proposal', 'invalid_workflow', 'invalid_workflow_parent', 'continuation_already_dispatched', 'distinct_command_required_no_replay', 'failed_workflow_no_automatic_retry', 'live_memory_index_skill_order_required', 'source_not_authored', 'shell_proposal_unavailable', 'tool_unavailable', 'memory_read_first', 'post_delivery_memory_only', 'live_index_first', 'unsupported_live_tool_arguments', 'invalid_tool_arguments', 'invalid_command_size_or_text', 'reaction_cache_unavailable', 'reaction_guide_missing', 'reaction_turn_unavailable', 'reaction_selection_unavailable', 'reaction_selection_refused', 'reaction_placement_unavailable', 'owned_receipt_unavailable', 'upstream_http_rejection', 'classification_incomplete', 'classification_invalid', 'model_refusal', 'provider_content_filter', 'upstream_stream_error', 'provider_unavailable', 'timeout', 'invalid_json', 'unclassified', 'response_too_large', 'invalid_response', 'incomplete_response']);
const activityStages = new Set(['reaction_admission', 'reaction_cache', 'reaction_selection', 'reaction_placement', 'shell_discovery', 'shell_receipt', 'shell_command_preparation', 'conversation_memory', 'work_classification', 'web_search', 'tool_selection', 'document_authoring', 'answer_stream', 'document_capture']);
export type KnotSelectionRepairDetail = { selectionIncident?: string; attempt?: number; attempts?: number; repairAttempts?: number; tokenLimit?: number; attemptedTokenLimit?: number; escalatedRetryRan?: boolean; outcome?: 'pending' | 'recovered' | 'degraded' | 'ended'; selectionRecovered?: boolean };
export type KnotActivityDetail = { stepPresentation?: 'authored_v1'; stepID?: string; stepLabel?: string; stepPurpose?: string; stepResult?: string; chatUpdate?: string; stepReceiptID?: string } & KnotSelectionRepairDetail & Partial<KnotAuthorTransportVitals> & Partial<KnotModelTransportFacts> & Partial<DocumentProgramDetail> & { programID?: string; sliceCount?: number; programSHA256?: string; sizeFacts?: DocumentSizeFacts; strategy?: KnotSelectionStrategy; promptSections?: KnotPromptSections; promptTargetExceeded?: boolean; terminationExit?: KnotSelectionTerminationExit; schemaHash?: string; deadlineMs?: number; elapsedMs?: number; promptBytes?: number; selectionPhase?: string; commandDispatched?: false; responseBytes?: number; contentBytes?: number; contentShape?: string; completionTokens?: number; promptTokens?: number; reasoningTokens?: number; model?: string; finishReason?: string; choicesPresent?: boolean; messagePresent?: boolean; toolCallsPresent?: boolean; argumentBytes?: number; invalidCall?: number; fields?: string[]; tool?: string; reason?: string; inputKind?: string; stage?: string; status?: number; commands?: number; commandLimit?: number; sourceMeasured?: boolean; finalMeasured?: boolean; proofPrepared?: boolean; proofConfirmed?: boolean };
export function safeKnotActivityDetail(value: unknown): KnotActivityDetail | undefined {
  if (!value || typeof value !== 'object') return undefined;
  const source = value as Record<string, unknown>, detail: KnotActivityDetail = {};
  if (source.stepPresentation === 'authored_v1') detail.stepPresentation = 'authored_v1';
  // Explicit agent-authored presentation only. Never authority or completion proof.
  if (typeof source.stepID === 'string' && /^[A-Za-z0-9:._-]{1,120}$/.test(source.stepID)) {
    detail.stepID = source.stepID;
    for (const [key, maximum] of [['stepLabel', 60], ['stepPurpose', 300], ['stepResult', 600], ['chatUpdate', 600]] as const) {
      const text = source[key];
      if (typeof text === 'string' && text.trim() && text.length <= maximum && !/[\x00-\x1f<>`]/.test(text)) detail[key] = key === 'stepLabel' || key === 'stepPurpose' ? text : text.trim();
    }
    if (typeof source.stepReceiptID === 'string' && /^[A-Za-z0-9:._-]{1,120}$/.test(source.stepReceiptID)) detail.stepReceiptID = source.stepReceiptID;
  }
  if (typeof source.check === 'string' && documentProgramChecks.some(check => check === source.check)) detail.check = source.check as DocumentProgramDetail['check'];
  const diagnostic = safeDocumentDiagnostic(source);
  if (diagnostic) Object.assign(detail, diagnostic);
  if (typeof source.rejectionID === 'string' && /^[a-f0-9-]{36}$/i.test(source.rejectionID)) detail.rejectionID = source.rejectionID;
  if (typeof source.rejectedBodySHA256 === 'string' && /^[a-f0-9]{64}$/.test(source.rejectedBodySHA256)) detail.rejectedBodySHA256 = source.rejectedBodySHA256;
  if (['retained', 'failed', 'not_received'].includes(String(source.retentionStatus))) detail.retentionStatus = source.retentionStatus as DocumentProgramDetail['retentionStatus'];
  if (source.deadlineSource === 'owned_turn') detail.deadlineSource = 'owned_turn';
  for (const [key, maximum] of [['sliceIndex', 31], ['sliceCharacters', 1000000], ['sliceCharacterLimit', documentProgramSliceCharacters], ['sliceByteLimit', documentProgramSliceBytes], ['requestedCharacters', 64000], ['expiresAt', 9999999999999]] as const) if (Number.isSafeInteger(source[key]) && Number(source[key]) >= 0 && Number(source[key]) <= maximum) detail[key] = Number(source[key]);
  if (typeof source.programID === 'string' && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(source.programID)) detail.programID = source.programID;
  if (typeof source.programSHA256 === 'string' && /^[a-f0-9]{64}$/.test(source.programSHA256)) detail.programSHA256 = source.programSHA256;
  if (Number.isSafeInteger(source.sliceCount) && Number(source.sliceCount) >= 0 && Number(source.sliceCount) <= 32) detail.sliceCount = Number(source.sliceCount);
  const sizeFacts = safeDocumentSizeFacts(source.sizeFacts);
  if (sizeFacts) detail.sizeFacts = sizeFacts;
  const fields = safeSelectionFields(source.fields);
  if (fields.length) detail.fields = fields;
  const tool = safeSelectionTool(source.tool);
  if (tool) detail.tool = tool;
  if (typeof source.terminationExit === 'string' && knotSelectionTerminationExits.some(exit => exit === source.terminationExit)) detail.terminationExit = source.terminationExit as KnotSelectionTerminationExit;
  if (typeof source.schemaHash === 'string' && /^[a-f0-9]{64}$/.test(source.schemaHash)) detail.schemaHash = source.schemaHash;
  if (typeof source.reason === 'string' && activityReasons.has(source.reason)) detail.reason = source.reason;
  if (typeof source.inputKind === 'string' && ['focus', 'type', 'key', 'click', 'scroll'].includes(source.inputKind)) detail.inputKind = source.inputKind;
  if (typeof source.stage === 'string' && activityStages.has(source.stage)) detail.stage = source.stage;
  if (typeof source.status === 'number' && Number.isInteger(source.status) && source.status >= 100 && source.status <= 599) detail.status = source.status;
  for (const key of ['commands', 'commandLimit'] as const) if (Number.isSafeInteger(source[key]) && (source[key] as number) >= 0 && (source[key] as number) <= shellCommandLimit) detail[key] = source[key] as number;
  if (typeof source.model === 'string' && knotTaskModels.some(model => model === source.model)) detail.model = source.model;
  if (typeof source.finishReason === 'string' && ['stop', 'tool_calls', 'length', 'content_filter', 'function_call', 'error', 'missing', 'unknown'].includes(source.finishReason)) detail.finishReason = source.finishReason;
  if (Number.isSafeInteger(source.argumentBytes) && (source.argumentBytes as number) >= 0 && (source.argumentBytes as number) <= 1000000) detail.argumentBytes = source.argumentBytes as number;
  if (typeof source.selectionIncident === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:[1-9][0-9]{0,2}$/i.test(source.selectionIncident)) detail.selectionIncident = source.selectionIncident.toLowerCase();
  if (typeof source.outcome === 'string' && ['pending', 'recovered', 'degraded', 'ended'].includes(source.outcome)) detail.outcome = source.outcome as KnotSelectionRepairDetail['outcome'];
  if (typeof source.selectionRecovered === 'boolean') detail.selectionRecovered = source.selectionRecovered;
  if (typeof source.escalatedRetryRan === 'boolean') detail.escalatedRetryRan = source.escalatedRetryRan;
  for (const [key, maximum] of [['responseBytes', 1000000], ['contentBytes', 1000000], ['completionTokens', 10000000], ['promptTokens', 10000000], ['reasoningTokens', 10000000], ['attempt', 16], ['attempts', 16], ['repairAttempts', 15], ['tokenLimit', 128000], ['attemptedTokenLimit', 128000]] as const) if (Number.isSafeInteger(source[key]) && (source[key] as number) >= 0 && (source[key] as number) <= maximum) detail[key] = source[key] as number;
  for (const [key, maximum] of [['deadlineMs', 1200000], ['elapsedMs', 1200000], ['promptBytes', 10000000]] as const) if (Number.isSafeInteger(source[key]) && (source[key] as number) >= 0 && (source[key] as number) <= maximum) detail[key] = source[key] as number;
  if (typeof source.strategy === 'string' && knotSelectionStrategies.some(strategy => strategy === source.strategy)) detail.strategy = source.strategy as KnotSelectionStrategy;
  if (typeof source.promptTargetExceeded === 'boolean') detail.promptTargetExceeded = source.promptTargetExceeded;
  if (source.promptSections && typeof source.promptSections === 'object' && !Array.isArray(source.promptSections)) {
    const sections = source.promptSections as Record<string, unknown>;
    const safe: KnotPromptSections = {};
    for (const key of knotPromptSectionKeys) if (Number.isSafeInteger(sections[key]) && (sections[key] as number) >= 0 && (sections[key] as number) <= 10000000) safe[key] = sections[key] as number;
    if (Object.keys(safe).length) detail.promptSections = safe;
  }
  if (Number.isSafeInteger(source.transportAttempt) && Number(source.transportAttempt) >= 1 && Number(source.transportAttempt) <= 3) detail.transportAttempt = Number(source.transportAttempt);
  if (Number.isSafeInteger(source.transportDelayMs) && Number(source.transportDelayMs) >= 0 && Number(source.transportDelayMs) <= 500) detail.transportDelayMs = Number(source.transportDelayMs);
  if (typeof source.transportOutcome === 'string' && ['attempt', 'retry', 'recovered', 'ended'].includes(source.transportOutcome)) detail.transportOutcome = source.transportOutcome as KnotModelTransportFacts['transportOutcome'];
  for (const [key, maximum] of [['transportCallCount', 3], ['transportElapsedMs', 1200000], ['transportFirstTokenMs', 1200000], ['transportChunkCount', 1000000], ['transportMaxIdleMs', 1200000]] as const) if (Number.isSafeInteger(source[key]) && Number(source[key]) >= 0 && Number(source[key]) <= maximum && (key !== 'transportCallCount' || Number(source[key]) >= 1)) detail[key] = Number(source[key]);
  if (source.transportStreaming === true) detail.transportStreaming = true;
  if (typeof source.transportTimeoutKind === 'string' && ['first_token', 'idle', 'owned_deadline'].includes(source.transportTimeoutKind)) detail.transportTimeoutKind = source.transportTimeoutKind as KnotAuthorTransportVitals['transportTimeoutKind'];
  for (const key of ['programBytes', 'modelResponseBytes', 'authoringResponses', 'authoringElapsedMs', 'authoringBytesPerSecond', 'programByteCeiling', 'budgetBytesPerSecond', 'marginPermille', 'authoringBudgetMs', 'completionReserveMs', 'turnBudgetMs', 'authoringBasePromptBytes', 'authoringTotalPromptBytes', 'authoringPromptOverageBytes', 'authoringReadBytes', 'authoringDevelopedBytes', 'authoringDescriptorBytes', 'turnElapsedMs'] as const) if (Number.isSafeInteger(source[key]) && Number(source[key]) >= 0 && Number(source[key]) <= 10000000) detail[key] = Number(source[key]);
  if (typeof source.sizeClass === 'string' && Object.hasOwn(knotCreationSizeClasses, source.sizeClass)) detail.sizeClass = source.sizeClass as KnotCreationSizeClass;
  if (typeof source.authoringPromptTargetExceeded === 'boolean') detail.authoringPromptTargetExceeded = source.authoringPromptTargetExceeded;
  if (source.commandDispatched === false) detail.commandDispatched = false;
  if (typeof source.selectionPhase === 'string' && ['browser_choice', 'closing_choice', 'document_build', 'document_authoring', 'artifact_authoring', 'tool_choice'].includes(source.selectionPhase)) detail.selectionPhase = source.selectionPhase;
  if (typeof source.contentShape === 'string' && ['absent', 'empty', 'json', 'partial_json', 'non_json'].includes(source.contentShape)) detail.contentShape = source.contentShape;
  if (Number.isSafeInteger(source.invalidCall) && (source.invalidCall as number) >= 0 && (source.invalidCall as number) < 48) detail.invalidCall = source.invalidCall as number;
  for (const key of ['choicesPresent', 'messagePresent', 'toolCallsPresent', 'sourceMeasured', 'finalMeasured', 'proofPrepared', 'proofConfirmed'] as const) if (typeof source[key] === 'boolean') detail[key] = source[key];
  return Object.keys(detail).length ? detail : undefined;
}
export type KnotActivity = { id: string; requestID: string; taskID?: string; sourceMessageID?: string; sequence: number; kind: string; label: string; recordedAt: string; detail?: KnotActivityDetail };
export function initializeKnotActivity(ctx: DurableObjectState): void {
  ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS knot_activity (id TEXT PRIMARY KEY, bot TEXT NOT NULL, conversation_id TEXT NOT NULL, recorded_at INTEGER NOT NULL, data TEXT NOT NULL)');
}
export function recordKnotActivity(ctx: DurableObjectState, bot: KnotBot, conversationID: string, requestID: string, sequence: number, kind: string, linkage: { taskID?: string; sourceMessageID?: string } = {}, detail?: unknown): void {
  if (!knotActivityLabels[kind] || !Number.isSafeInteger(sequence) || sequence < 1 || sequence > 1000) return;
  // All writers (including delayed browser/orchestrator completions) honor the
  // same permanent conversation/account erasure tombstones as captured files.
  if (ctx.storage.sql.exec("SELECT 1 FROM knot_document_deletions WHERE conversation_id IN (?, '*')", conversationID.toLowerCase()).toArray().length) return;
  const now = Date.now();
  const id = `${requestID}:${sequence}`;
  const validID = (value: unknown): value is string => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
  const value: KnotActivity = { id, requestID, sequence, kind, label: knotActivityLabels[kind], recordedAt: new Date(now).toISOString(),
    taskID: validID(linkage.taskID) ? linkage.taskID.toLowerCase() : requestID.toLowerCase(),
    sourceMessageID: validID(linkage.sourceMessageID) ? linkage.sourceMessageID.toLowerCase() : undefined, detail: safeKnotActivityDetail(detail) };
  ctx.storage.transactionSync(() => {
    ctx.storage.sql.exec('DELETE FROM knot_activity WHERE recorded_at < ?', now - 86400000);
    ctx.storage.sql.exec('INSERT OR IGNORE INTO knot_activity VALUES (?, ?, ?, ?, ?)', id, bot, conversationID, now, JSON.stringify(value));
    ctx.storage.sql.exec('DELETE FROM knot_activity WHERE id IN (SELECT id FROM knot_activity ORDER BY recorded_at DESC, id DESC LIMIT -1 OFFSET 2400)');
  });
}
/** Append-only outcome observations project onto the original rejection on read.
 * Neither historical rows nor their original attempt/token/shape facts change. */
export function resolvedKnotSelectionActivity(activities: KnotActivity[]): KnotActivity[] {
  const outcomes = new Map<string, KnotActivity>();
  for (const activity of activities) {
    const incident = activity.detail?.selectionIncident;
    if (activity.kind !== 'tool_selection_outcome' || !incident || !incident.startsWith(activity.requestID.toLowerCase() + ':') || !['recovered', 'degraded', 'ended'].includes(activity.detail?.outcome ?? '')) continue;
    const key = activity.requestID + ':' + incident, previous = outcomes.get(key);
    if (!previous || activity.sequence > previous.sequence) outcomes.set(key, activity);
  }
  return activities.map(activity => {
    const resolution = outcomes.get(activity.requestID + ':' + activity.detail?.selectionIncident);
    if (!resolution || !['tool_selection_retry', 'tool_selection_rejected', 'tool_selection_partial', 'tool_selection_outcome'].includes(activity.kind)) return activity;
    const outcome = resolution.detail!.outcome, selectionRecovered = resolution.detail!.selectionRecovered;
    return { ...activity, label: outcome === 'recovered' ? 'Tool selection recovered; task success not implied' : outcome === 'degraded' ? 'Selection incident; turn finished with limits' : 'Selection incident; turn ended', detail: { ...activity.detail, outcome, selectionRecovered, attempts: resolution.detail!.attempts, repairAttempts: resolution.detail!.repairAttempts, attemptedTokenLimit: resolution.detail!.attemptedTokenLimit, escalatedRetryRan: resolution.detail!.escalatedRetryRan } };
  });
}
export function readKnotActivity(ctx: DurableObjectState, bot: KnotBot, conversationID: string): KnotActivity[] {
  ctx.storage.sql.exec('DELETE FROM knot_activity WHERE recorded_at < ?', Date.now() - 86400000);
  const activities = ctx.storage.sql.exec<{ data: string }>('SELECT data FROM knot_activity WHERE bot = ? AND conversation_id = ? ORDER BY recorded_at DESC, id DESC LIMIT 400', bot, conversationID).toArray().map(row => JSON.parse(row.data) as KnotActivity);
  return resolvedKnotSelectionActivity(activities);
}
