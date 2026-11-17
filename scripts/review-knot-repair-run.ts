// Fresh November 14 paid-repair scope evidence. No task/command/review/capture
// replay. --export-rejection is an authenticated read; --review is local only.
import { readFileSync, writeFileSync, existsSync, mkdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash } from 'node:crypto';
import { AcceptanceSkillProvenance, assertAcceptanceIdentity } from './knot-acceptance-provenance';
import { replayDocumentResponse, rejectedDocumentRecordByteLimit } from '../functions/knot-document-replay';
import { documentDiagnostic, safeDocumentDiagnostic } from '../functions/knot-document-diagnostics';
const args = process.argv.slice(2), mode = args[0], scope = args[1];
function fact(value: unknown, code: string): asserts value { if (!value) throw new Error(code); }
const hash = (value: string | Uint8Array) => createHash('sha256').update(value).digest('hex');
const loadAt = (directory: string, name: string): any => JSON.parse(readFileSync(join(directory, name), 'utf8'));
const base = join(tmpdir(), 'knot-acceptance-uf26aun6d49w1tsjsm2u9');
const accountID = 'e00a9064-5f85-40bb-9f44-8bd60f90d24a', workspaceID = 'whisper-' + accountID;
const backend = 'https://uf26aun6d49w1tsjsm2u9-backend.rork.app';
function immutable(path: string, bytes: Uint8Array, privateFile = false) {
  if (existsSync(path)) fact(readFileSync(path).equals(bytes), 'immutable_evidence_collision');
  else writeFileSync(path, bytes, { flag: 'wx', mode: privateFile ? 0o600 : 0o644 });
}
async function main() {
  fact(args.length === 2 && ['--export-rejection', '--review'].includes(mode) && /^20261114-[a-z][a-z0-9-]{0,60}$/.test(scope ?? ''), 'explicit_repair_scope_required');
  const once = loadAt(base, 'recipes-repair-' + scope + '-once-intent.json');
  fact(once.authorization === 'explicit_user_paid_document_repair_iterations_2026_11_14' && once.scope === scope && once.accountID === accountID && once.workspaceID === workspaceID && once.backend === backend && once.noAutomaticRetry && once.freshTaskOnly && once.allHistoricalIntentsPreserved && typeof once.directory === 'string' && once.directory.startsWith(base + '/battery-'), 'new_authorized_scope_binding');
  const root = join(once.directory, 'recipe-pdf'), load = (name: string) => loadAt(root, name);
  const result = load('result.json'), intent = load('intent.json'), setup = loadAt(base, 'setup-repair-' + scope + '.json');
  const taskID = result.taskID, conversationID = result.conversationID, sourceMessageID = result.sourceMessageID;
  for (const item of [intent, result]) fact(item.accountID === accountID && item.workspaceID === workspaceID && item.requestID === taskID && item.taskID === taskID && item.conversationID === conversationID && item.sourceMessageID === sourceMessageID, 'exact_owned_run');
  fact(result.stopConfirmed && result.completed && intent.taskModelConsentVersion === 'knot_task_models_v1' && result.servingBuilds.worker === once.expectedBuild && setup.servingBuilds['/knot/shell/events'].worker === once.expectedBuild && setup.servingBuilds['/knot/shell/events'].actor === once.expectedBuild && Date.parse(intent.startedAt) >= Date.parse(setup.observedAt) && Date.parse(intent.startedAt) - Date.parse(setup.observedAt) < 300000, 'canonical_completed_evidence');
  const frames = readFileSync(join(root, 'frames.jsonl'), 'utf8').trim().split('\n').map(value => JSON.parse(value));
  fact(frames.length === result.frameCount && frames.every((frame: any, index: number) => frame.requestID === taskID && frame.sequence === index + 1 && (!frame.activity || frame.activity.taskID === taskID && frame.activity.sourceMessageID === sourceMessageID)), 'ordered_owned_frames');
  fact(frames.find((frame: any) => frame.type === 'complete')?.clientElapsedMs === result.completionReceivedMs, 'completion_clock');
  const activities = frames.filter((frame: any) => frame.activity).map((frame: any) => frame.activity);
  const rejected = activities.find((activity: any) => activity.kind === 'tool_request_rejected' && activity.detail?.rejectionID)?.detail;
  const privatePath = join(root, 'rejected-response-private.json');
  fact(rejected?.retentionStatus === 'retained' && result.workIncomplete && result.issue === 'document_program_invalid' && !result.reply && result.documents.length === 0, 'retained_failed_author_scope_only');
  const parentID = result.executions.at(-1)?.proposalID;
  fact(typeof parentID === 'string' && /^[a-f0-9-]{36}$/.test(parentID) && result.executions.at(-1).operation === 'workspace_inventory', 'failed_author_parent');
  const parent = load(parentID + '-proposal.json'), parentReceipt = load(parentID + '-result.json');
  assertAcceptanceIdentity(parent, parentReceipt, { requestID: taskID, conversationID, sourceMessageID });
  const rejectionID = rejected.rejectionID, bodyHash = rejected.rejectedBodySHA256;
  function verifyRecord(record: any) {
    fact(record.id === rejectionID && record.version === 'document_author_rejection_v1' && record.owner?.workspace === workspaceID && record.owner.bot === 'main' && record.owner.conversationID === conversationID && record.owner.rootID === taskID && record.owner.sourceMessageID === sourceMessageID && record.owner.parentID === parentID, 'private_owner_binding');
    fact(record.response?.complete === true && hash(record.response.content) === bodyHash && record.rejectedBodySHA256 === bodyHash && Buffer.byteLength(record.response.content) === rejected.contentBytes && record.response.envelope?.choices?.[0]?.message?.content === record.response.content && record.schemaHash === hash(JSON.stringify(record.schema)) && record.schemaHash === rejected.schemaHash, 'private_complete_content_schema_binding');
  }
  if (mode === '--export-rejection') {
    fact(!existsSync(privatePath), 'private_export_already_exists_use_local_review');
    const account = loadAt(base, 'account.json');
    fact(account.accountID === accountID && account.projectRef === 'uryyyegnbtlmyhqlgndy' && typeof account.accessToken === 'string', 'existing_dedicated_account_required');
    const response = await fetch(backend + '/knot/shell/document-program/rejection', { method: 'POST', redirect: 'error', headers: { 'X-Whisper-Authorization': 'Bearer ' + account.accessToken, 'Content-Type': 'application/json' }, body: JSON.stringify({ bot: 'main', conversationID, proposalID: parentID, rejectionID }), signal: AbortSignal.timeout(25000) });
    fact(response.ok && response.body && response.headers.get('Cache-Control') === 'no-store' && response.headers.get('X-Knot-Worker-Build') === once.expectedBuild && response.headers.get('X-Knot-Actor-Build') === once.expectedBuild, 'owned_export_unavailable');
    const reader = response.body.getReader(), chunks: Uint8Array[] = []; let size = 0;
    try { for (;;) { const part = await reader.read(); if (part.done) break; size += part.value.length; fact(size <= rejectedDocumentRecordByteLimit, 'private_record_capacity'); chunks.push(part.value); } }
    finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
    const bytes = Buffer.concat(chunks), record = JSON.parse(new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(bytes));
    verifyRecord(record); immutable(privatePath, bytes, true);
    console.log(JSON.stringify({ taskID, rejectionID, authenticatedReadOnlyExport: 'passed', exportedBytes: size, exactOwnerBinding: true, rejectedBodySHA256: bodyHash, privateContentPrinted: false, additionalProviderCalls: 0, commandsExecuted: 0 }));
    return;
  }
  fact(statSync(privatePath).size <= rejectedDocumentRecordByteLimit, 'private_record_capacity');
  const record = load('rejected-response-private.json'); verifyRecord(record);
  let replayedDiagnostic;
  try { replayDocumentResponse(record.response.envelope, record.context); }
  catch (error) { replayedDiagnostic = documentDiagnostic(error, 'offline_replay'); }
  const diagnostic = safeDocumentDiagnostic(record.diagnostic);
  fact(diagnostic && JSON.stringify(replayedDiagnostic) === JSON.stringify(diagnostic) && JSON.stringify(safeDocumentDiagnostic(rejected)) === JSON.stringify(diagnostic) && !diagnostic.unexplained, 'actual_body_replay_matches');
  const parsed = JSON.parse(record.response.content), blankCells: string[] = [];
  for (const [s, section] of parsed.sections.entries()) for (const [b, block] of section.blocks.entries()) if (block.kind === 'table') for (const [r, row] of block.rows.entries()) for (const [c, cell] of row.entries()) if (typeof cell === 'string' && !cell.trim()) blankCells.push(`$.sections[${s}].blocks[${b}].rows[${r}][${c}]`);
  fact(diagnostic.branch !== 'text_nonblank' || blankCells.includes(diagnostic.fieldPath), 'reported_blank_cell_confirmed');
  const attempts = activities.filter((activity: any) => activity.kind === 'document_program_attempt'), transports = activities.filter((activity: any) => activity.kind === 'model_transport_outcome' && activity.detail?.stage === 'document_authoring');
  fact(attempts.length === 1 && transports.length === 1 && !activities.some((activity: any) => ['document_program_retry', 'document_program_slice', 'document_program_sealed'].includes(activity.kind)), 'one_author_response_no_retry');
  const transport = transports[0].detail;
  fact(transport.model === 'anthropic/claude-sonnet-4.6' && transport.transportCallCount === 1 && transport.transportStreaming === true && rejected.authoringResponses === 1 && rejected.programBytes === 0 && rejected.sliceCount === 0 && rejected.finishReason === 'stop', 'transport_and_rejection_binding');
  const prior = join(base, 'battery-2026-11-14T03-41-24-088Z', 'recipe-pdf');
  const recoveredPath = join(once.directory, 'recovered-original-guide-provenance.json');
  const recovered = existsSync(recoveredPath);
  const baseline = recovered
    ? { taskID: 'b936a45f-b94a-4c5c-8ac6-b0c92e894466', requestID: 'b936a45f-b94a-4c5c-8ac6-b0c92e894466', conversationID: 'f5fa4af7-6299-4fd6-83f7-1275112879d9', sourceMessageID: 'b7b7d40a-75da-4e3f-ae51-08178aa6e5f5', completionReceivedMs: loadAt('deliveries', 'recipes-structured-attempt-19623939.json').prospectivePlan.baselineCompletionMs }
    : loadAt(prior, 'result.json');
  if (recovered) fact(intent.ask === 'Create and deliver a beautifully designed PDF with three high-protein recipes suitable for fat loss. For each recipe include measured ingredients, clear cooking steps, approximate calories and protein per serving, and an explanation of why it supports a high-protein fat-loss diet. Make the recipes practical and substantive, with a considered editorial layout, not a decorative list.' && baseline.completionReceivedMs === 603097, 'committed_baseline_and_exact_known_ask');
  else fact(baseline.taskID === 'b936a45f-b94a-4c5c-8ac6-b0c92e894466' && baseline.completed && !baseline.issue && loadAt(prior, 'intent.json').ask === intent.ask, 'same_ask_baseline');
  const provenance = new AcceptanceSkillProvenance({ accountID, workspaceID }), originalID = '9924aed8-6462-4db0-a779-a0f0400495b0';
  const original = recovered ? JSON.parse(readFileSync(recoveredPath, 'utf8')) : { proposal: loadAt(prior, originalID + '-proposal.json'), original: loadAt(prior, originalID + '-result.json') };
  fact(original.proposal.id === originalID && hash(JSON.stringify([original.original.stdout, original.original.stderr])) === 'f82c7eb4ecd411664199f5d16f42afe4dc53651a69400c7537685d72bb78be0e', 'original_guide_hash');
  provenance.remember(original.proposal, original.original, { requestID: baseline.requestID, conversationID: baseline.conversationID, sourceMessageID: baseline.sourceMessageID });
  const commands = result.executions.map((execution: any) => {
    const id = execution.proposalID, proposal = load(id + '-proposal.json'), receipt = load(id + '-result.json');
    assertAcceptanceIdentity(proposal, receipt, { requestID: taskID, conversationID, sourceMessageID });
    fact(receipt.status === 'completed' && receipt.exitCode === 0 && receipt.terminationConfirmed && receipt.outputComplete && !receipt.truncated && !receipt.contextTruncated && hash(receipt.stdout) === execution.stdoutSHA256, 'complete_execution_evidence');
    if (receipt.cachedData) {
      fact(receipt.cachedData.sourceProposalID === originalID && provenance.acceptCache(proposal, receipt, { requestID: taskID, conversationID, sourceMessageID }), 'strict_original_cached_guide');
      return { proposalID: id, operation: execution.operation, newExecution: false, originalGuideReceipt: originalID, completeOutputMatchesOriginal: true, sessionID: receipt.sessionID };
    }
    const boundary = receipt.commandReceipt, log = load(id + '-log.json');
    fact(boundary?.source === 'harness_shell_boundaries_v1' && boundary.proposal_id === id && boundary.session_id === receipt.sessionID && boundary.exit_code === 0 && boundary.background_jobs === false && log.session_id === receipt.sessionID && log.stdout_from === 0 && log.stderr_from === 0 && !log.truncated && receipt.providerReceipt?.user_id === workspaceID && receipt.providerReceipt.output_complete === true && receipt.providerReceipt.output_late_bytes === 0, 'execution_receipt_boundary');
    for (const stream of ['stdout', 'stderr']) {
      const data = Buffer.from(log[stream]), start = boundary[stream + '_start'], end = boundary[stream + '_end'];
      fact(Number.isSafeInteger(start) && Number.isSafeInteger(end) && start >= 0 && end >= start && end <= data.length && data.subarray(start, end).equals(Buffer.from(receipt[stream])), 'full_log_bytes_match_receipt');
    }
    return { proposalID: id, operation: execution.operation, newExecution: true, exactLogBoundaryMatches: true, sessionID: receipt.sessionID };
  });
  const events = load('events.json');
  fact(commands.length === 4 && commands.filter((entry: any) => entry.newExecution).length === 3 && commands.every((entry: any) => entry.sessionID === 'cfa2086e-cd18-45df-9025-e75ba8568225') && events.records.length === 4 && events.documents.length === 0 && events.records.every((row: any) => row.taskID === taskID && row.sourceMessageID === sourceMessageID && row.state === 'finished' && row.workCommands === 0 && row.workCost === 0), 'no_document_execution_or_delivery');
  const report = {
    title: 'Recipes repair iteration — strict author rejection', scope, taskID, conversationID, sourceMessageID, sourceBuildSHA256: once.expectedBuild,
    preflightObservedAt: setup.observedAt, startedAt: result.startedAt, endedAt: result.endedAt, outcome: 'failed_before_source_build_proof_or_capture',
    timing: { incompleteCompletionEventMs: result.completionReceivedMs, streamEndedMs: result.streamEndedMs, evidenceCollectionMs: result.evidenceCollectionMs, totalMs: result.elapsedMs, authorProviderMs: transport.transportElapsedMs, firstAuthorContentMs: transport.transportFirstTokenMs, successfulDeliveryMs: null },
    authoring: { model: transport.model, authorResponses: 1, authorProviderCalls: 1, automaticAuthorRetries: 0, returnedContentBytes: rejected.contentBytes, completionTokens: rejected.completionTokens, promptTokens: rejected.promptTokens, finishReason: rejected.finishReason, promptBytesIncludingContract: rejected.authoringTotalPromptBytes, completeReadMessageBytes: rejected.authoringReadBytes, sealedProgramBytes: 0 },
    diagnostic, actualRetainedResponseReplay: { verified: true, completeReassembledContent: true, originalWireBytesClaimed: false, bodyHashVerified: true, schemaHashVerified: true, ownerAndParentVerified: true, diagnosticMatchesProduction: true, rejectedBodySHA256: bodyHash, blankCellPaths: blankCells, privateContentPublished: false, additionalProviderCalls: 0, commandsExecuted: 0 },
    comparison: { exactSameAsk: true, baselineSuccessfulCompletionMs: baseline.completionReceivedMs, baselineOriginalRawEvidenceAvailable: !recovered, recoveredGuideOriginalIndependentlyVerified: recovered, successfulDeliveryImprovementEstablished: false },
    evidence: { orderedFrames: frames.length, ownedReceipts: 4, newShellInputs: 3, sameSessionCompleteCachedGuide: 1, meteredWorkCommands: 0, workCeiling: 10000, capturedDocuments: 0, sourceBuildProofCommands: 0, contentChecks: 0, pageReviews: 0, historicalTaskOrCommandReplay: false, terminalIncompleteOutcome: true, stopConfirmed: result.stopConfirmed }, commands,
    scopeNote: 'One deliberate newly authorized paid repair iteration. Time to failure is not successful delivery latency. Rejected content stays in private storage; it was not patched, executed or substituted for a PDF. Native/device acceptance remains separate.'
  };
  mkdirSync('deliveries', { recursive: true });
  const path = 'deliveries/recipes-repair-' + taskID.slice(0, 8) + '.json';
  immutable(path, Buffer.from(JSON.stringify(report, null, 2) + '\n'));
  console.log(JSON.stringify({ report: path, ...report }, null, 2));
}
main().catch(error => { console.error(JSON.stringify({ status: 'unconfirmed', reason: error instanceof Error && /^[a-z_]+$/.test(error.message) ? error.message : 'scoped_review_unavailable', credentialsPrinted: false })); process.exitCode = 2; });
