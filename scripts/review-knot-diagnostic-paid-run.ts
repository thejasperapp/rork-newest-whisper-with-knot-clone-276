// Exact November 14 paid diagnostic run. --export makes ONE authenticated
// read-only rejection export; --review uses only retained local evidence.
// No author call, command execution/resume, review model or capture is made.
import { readFileSync, writeFileSync, existsSync, mkdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash } from 'node:crypto';
import { AcceptanceSkillProvenance, assertAcceptanceIdentity } from './knot-acceptance-provenance';
import { replayDocumentResponse, rejectedDocumentRecordByteLimit } from '../functions/knot-document-replay';
import { documentDiagnostic, safeDocumentDiagnostic } from '../functions/knot-document-diagnostics';
import { structuredDocumentSchema } from '../functions/knot-document-structured';
const accountID = 'e00a9064-5f85-40bb-9f44-8bd60f90d24a', workspaceID = 'whisper-' + accountID;
const taskID = '129ba717-8b7f-43c3-b9ff-107c09ea1de4', conversationID = '363dbf48-2c8b-4b1c-a783-6737740a453f', sourceMessageID = 'e60a72ed-af41-460d-a254-ae7c36e31de8';
const parentID = '36e104c9-5951-43fa-a077-00372fe8a4bc', rejectionID = 'e042c218-8131-4b91-8918-d7ad8369bc8a';
const expectedBuild = '541c8ec637fcc16c6586ee08496fd66b6827501f03273aaa8f2e600888e5d864';
const bodyHash = 'e6476f994315ddfa76d4b40470714966f0b871c810ad551d302726f24b84d373';
const backend = 'https://uf26aun6d49w1tsjsm2u9-backend.rork.app';
const base = join(tmpdir(), 'knot-acceptance-uf26aun6d49w1tsjsm2u9');
const battery = 'battery-2026-11-14T05-51-51-061Z';
const root = join(base, battery, 'recipe-pdf');
const prior = join(base, 'battery-2026-11-14T03-41-24-088Z', 'recipe-pdf');
const privatePath = join(root, 'rejected-response-private.json');
const loadAt = (directory: string, name: string): any => JSON.parse(readFileSync(join(directory, name), 'utf8'));
const load = (name: string) => loadAt(root, name);
const hash = (value: string | Uint8Array) => createHash('sha256').update(value).digest('hex');
function fact(value: unknown, code: string): asserts value { if (!value) throw new Error(code); }
function immutable(path: string, bytes: Uint8Array, privateFile = false) {
  if (existsSync(path)) fact(readFileSync(path).equals(bytes), 'immutable_record_collision');
  else writeFileSync(path, bytes, { flag: 'wx', mode: privateFile ? 0o600 : 0o644 });
}
function verifyIdentity() {
  const result = load('result.json'), intent = load('intent.json');
  for (const item of [result, intent]) fact(item.accountID === accountID && item.workspaceID === workspaceID && item.taskID === taskID && item.requestID === taskID && item.conversationID === conversationID && item.sourceMessageID === sourceMessageID, 'exact_run_identity_required');
  const once = loadAt(base, 'recipes-diagnostic-paid-once-intent.json'), setup = loadAt(base, 'setup-diagnostic-paid.json');
  fact(once.authorization === 'explicit_user_one_new_paid_document_request_2026_11_14' && once.noAutomaticRetry && once.allHistoricalIntentsPreserved && once.directory === join(base, battery) && once.accountID === accountID && once.workspaceID === workspaceID && once.backend === backend && once.expectedBuild === expectedBuild && once.selectedKeys.length === 1 && once.selectedKeys[0] === 'recipe-pdf' && once.taskModelConsentVersion === 'knot_task_models_v1' && intent.taskModelConsentVersion === once.taskModelConsentVersion, 'new_single_paid_scope');
  for (const name of ['recipes-structured-run-once-intent.json', 'recipes-structured-replacement-once-intent.json']) {
    const old = loadAt(base, name); fact(old.noAutomaticRetry && old.accountID === accountID && old.directory !== once.directory, 'historical_scope_preserved');
  }
  fact(setup.accountID === accountID && setup.managedAuthentication === 'passed' && setup.sidecarDiscovery === 'passed' && setup.servingBuilds['/knot/shell/events'].worker === expectedBuild && setup.servingBuilds['/knot/shell/events'].actor === expectedBuild && Date.parse(intent.startedAt) >= Date.parse(setup.observedAt) && Date.parse(intent.startedAt) - Date.parse(setup.observedAt) < 300000, 'canonical_preflight_required');
  return { result, intent, setup };
}
async function exportRecord() {
  verifyIdentity();
  fact(!existsSync(privatePath), 'private_export_already_exists_use_local_review');
  const account = loadAt(base, 'account.json');
  fact(account.accountID === accountID && account.projectRef === 'uryyyegnbtlmyhqlgndy' && typeof account.accessToken === 'string', 'existing_dedicated_account_required');
  const response = await fetch(backend + '/knot/shell/document-program/rejection', { method: 'POST', redirect: 'error', headers: { 'X-Whisper-Authorization': 'Bearer ' + account.accessToken, 'Content-Type': 'application/json' }, body: JSON.stringify({ bot: 'main', conversationID, proposalID: parentID, rejectionID }), signal: AbortSignal.timeout(25000) });
  fact(response.ok && response.body && response.headers.get('Cache-Control') === 'no-store' && response.headers.get('X-Knot-Worker-Build') === expectedBuild && response.headers.get('X-Knot-Actor-Build') === expectedBuild, 'owned_export_unavailable');
  const reader = response.body.getReader(), chunks: Uint8Array[] = []; let size = 0;
  try {
    for (;;) { const part = await reader.read(); if (part.done) break; size += part.value.length; fact(size <= rejectedDocumentRecordByteLimit, 'private_record_capacity'); chunks.push(part.value); }
  } finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
  const bytes = Buffer.concat(chunks);
  const record = JSON.parse(new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(bytes));
  fact(record.id === rejectionID && record.version === 'document_author_rejection_v1' && record.owner?.workspace === workspaceID && record.owner.bot === 'main' && record.owner.conversationID === conversationID && record.owner.rootID === taskID && record.owner.sourceMessageID === sourceMessageID && record.owner.parentID === parentID && record.response?.complete === true && hash(record.response.content) === bodyHash && record.rejectedBodySHA256 === bodyHash, 'export_owner_and_content_binding');
  immutable(privatePath, bytes, true);
  console.log(JSON.stringify({ taskID, rejectionID, authenticatedReadOnlyExport: 'passed', exportedBytes: size, exactOwnerBinding: true, rejectedBodySHA256: bodyHash, privateContentPrinted: false, additionalProviderCalls: 0, commandsExecuted: 0 }));
}
function review() {
  const { result, intent, setup } = verifyIdentity(), baseline = loadAt(prior, 'result.json');
  fact(baseline.taskID === 'b936a45f-b94a-4c5c-8ac6-b0c92e894466' && baseline.completed && !baseline.issue && baseline.completionReceivedMs === 603097 && loadAt(prior, 'intent.json').ask === intent.ask, 'same_ask_baseline');
  fact(result.completed && result.workIncomplete && result.issue === 'document_program_invalid' && result.stopConfirmed && !result.reply && result.documents.length === 0 && result.servingBuilds.worker === expectedBuild && result.completionReceivedMs === 113624 && result.elapsedMs === 115731 && Date.parse(result.endedAt) - Date.parse(result.startedAt) === result.elapsedMs, 'failed_paid_result');
  const frames = readFileSync(join(root, 'frames.jsonl'), 'utf8').trim().split('\n').map(value => JSON.parse(value));
  fact(frames.length === 27 && frames.length === result.frameCount && frames.every((frame: any, i: number) => frame.requestID === taskID && frame.sequence === i + 1 && (!frame.activity || frame.activity.taskID === taskID && frame.activity.sourceMessageID === sourceMessageID)), 'ordered_owned_frames');
  fact(frames.find((frame: any) => frame.type === 'complete')?.clientElapsedMs === result.completionReceivedMs, 'completion_clock_binding');
  const activities = frames.filter((frame: any) => frame.activity).map((frame: any) => frame.activity);
  const rejected = activities.find((activity: any) => activity.kind === 'tool_request_rejected')?.detail;
  const attempts = activities.filter((activity: any) => activity.kind === 'document_program_attempt');
  const transports = activities.filter((activity: any) => activity.kind === 'model_transport_outcome' && activity.detail?.stage === 'document_authoring');
  fact(attempts.length === 1 && transports.length === 1 && !activities.some((activity: any) => ['document_program_retry', 'document_program_slice', 'document_program_sealed'].includes(activity.kind)), 'one_author_response_no_retry');
  const transport = transports[0].detail;
  fact(transport.model === 'anthropic/claude-sonnet-4.6' && transport.transportCallCount === 1 && transport.transportElapsedMs === 97171 && transport.transportOutcome === 'recovered' && transport.transportStreaming === true && rejected?.retentionStatus === 'retained' && rejected.rejectionID === rejectionID && rejected.rejectedBodySHA256 === bodyHash && rejected.contentBytes === 17254 && rejected.authoringResponses === 1 && rejected.programBytes === 0 && rejected.sliceCount === 0 && rejected.finishReason === 'stop', 'transport_and_rejection_binding');
  fact(statSync(privatePath).size <= rejectedDocumentRecordByteLimit, 'private_record_capacity');
  const record = load('rejected-response-private.json');
  fact(record.id === rejectionID && record.owner?.workspace === workspaceID && record.owner.rootID === taskID && record.owner.conversationID === conversationID && record.owner.sourceMessageID === sourceMessageID && record.owner.parentID === parentID && record.owner.bot === 'main', 'private_owner_binding');
  fact(record.response.complete === true && hash(record.response.content) === bodyHash && record.rejectedBodySHA256 === bodyHash && Buffer.byteLength(record.response.content) === rejected.contentBytes && record.response.envelope?.choices?.[0]?.message?.content === record.response.content && record.schemaHash === hash(JSON.stringify(record.schema)) && record.schemaHash === hash(JSON.stringify(structuredDocumentSchema)) && record.schemaHash === rejected.schemaHash, 'private_complete_content_schema_binding');
  let replayedDiagnostic;
  try { replayDocumentResponse(record.response.envelope, record.context); }
  catch (error) { replayedDiagnostic = documentDiagnostic(error, 'offline_replay'); }
  const diagnostic = safeDocumentDiagnostic(record.diagnostic);
  fact(diagnostic && JSON.stringify(replayedDiagnostic) === JSON.stringify(diagnostic) && JSON.stringify(safeDocumentDiagnostic(rejected)) === JSON.stringify(diagnostic) && diagnostic.branch === 'text_nonblank' && diagnostic.fieldPath === '$.sections[1].blocks[2].rows[6][2]' && !diagnostic.unexplained, 'actual_body_replay_matches');
  const parsed = JSON.parse(record.response.content), table = parsed.sections[1].blocks[2], cell = table.rows[6][2];
  fact(table.kind === 'table' && typeof cell === 'string' && cell.trim().length === 0, 'blank_table_cell_confirmed');
  const events = load('events.json');
  fact(events.records.length === 4 && events.documents.length === 0 && events.records.every((row: any) => row.taskID === taskID && row.sourceMessageID === sourceMessageID && row.state === 'finished' && row.workCommands === 0 && row.workCost === 0), 'no_document_execution_or_delivery');
  const provenance = new AcceptanceSkillProvenance({ accountID, workspaceID }), originalID = '9924aed8-6462-4db0-a779-a0f0400495b0';
  provenance.remember(loadAt(prior, originalID + '-proposal.json'), loadAt(prior, originalID + '-result.json'), { requestID: baseline.requestID, conversationID: baseline.conversationID, sourceMessageID: baseline.sourceMessageID });
  const commands = result.executions.map((execution: any) => {
    const id = execution.proposalID, proposal = load(id + '-proposal.json'), receipt = load(id + '-result.json');
    assertAcceptanceIdentity(proposal, receipt, { requestID: taskID, conversationID, sourceMessageID });
    fact(receipt.status === 'completed' && receipt.exitCode === 0 && receipt.terminationConfirmed && receipt.outputComplete && !receipt.truncated && !receipt.contextTruncated && hash(receipt.stdout) === execution.stdoutSHA256, 'complete_execution_evidence');
    if (receipt.cachedData) {
      fact(id === '55632984-9542-4be2-a8ce-039b3acdd440' && receipt.cachedData.sourceProposalID === originalID && provenance.acceptCache(proposal, receipt, { requestID: taskID, conversationID, sourceMessageID }), 'strict_original_cached_guide');
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
  fact(commands.length === 4 && commands.filter((entry: any) => entry.newExecution).length === 3 && commands.every((entry: any) => entry.sessionID === 'cfa2086e-cd18-45df-9025-e75ba8568225'), 'same_live_session_three_new_inputs');
  const report = {
    title: 'Paid recipes document test — blank table cell rejected', taskID, conversationID, sourceMessageID, sourceBuildSHA256: expectedBuild,
    preflightObservedAt: setup.observedAt, startedAt: result.startedAt, endedAt: result.endedAt,
    outcome: 'failed_before_source_build_proof_or_capture',
    timing: { incompleteCompletionEventMs: result.completionReceivedMs, streamEndedMs: result.streamEndedMs, evidenceCollectionMs: result.evidenceCollectionMs, totalMs: result.elapsedMs, authorProviderMs: transport.transportElapsedMs, firstAuthorContentMs: transport.transportFirstTokenMs, successfulDeliveryMs: null },
    authoring: { model: transport.model, authorResponses: 1, authorProviderCalls: 1, automaticAuthorRetries: 0, returnedContentBytes: rejected.contentBytes, completionTokens: rejected.completionTokens, promptTokens: rejected.promptTokens, finishReason: rejected.finishReason, promptBytesIncludingContract: rejected.authoringTotalPromptBytes, completeReadMessageBytes: rejected.authoringReadBytes, sealedProgramBytes: 0 },
    diagnostic, actualRetainedResponseReplay: { verified: true, completeReassembledContent: true, originalWireBytesClaimed: false, bodyHashVerified: true, schemaHashVerified: true, ownerAndParentVerified: true, diagnosticMatchesProduction: true, rejectedBodySHA256: bodyHash, blankCellConfirmed: true, privateContentPublished: false, additionalProviderCalls: 0, commandsExecuted: 0 },
    comparison: { exactSameAsk: true, baselineSuccessfulCompletionMs: 603097, previousFailedAttemptMs: 270443, currentFailedAttemptMs: result.completionReceivedMs, successfulDeliveryImprovementEstablished: false, note: 'Ending after one rejected response avoids the former three-attempt failure loop. This is time to failure, not successful PDF delivery latency. The new actual-body cause is established only for this new run; historical discarded responses remain unprovable.' },
    evidence: { orderedFrames: frames.length, ownedReceipts: 4, newShellInputs: 3, sameSessionCompleteCachedGuide: 1, meteredWorkCommands: 0, workCeiling: 10000, capturedDocuments: 0, sourceBuildProofCommands: 0, contentChecks: 0, pageReviews: 0, historicalTaskOrCommandReplay: false, terminalIncompleteOutcome: true, stopConfirmed: result.stopConfirmed }, commands,
    scope: 'Exactly one newly authorized paid task via the existing dedicated account and canonical backend. No owner-account/device UI testing, no second paid submission, no fallback, content shortening, relaxed validator, historical task replay or substituted PDF. This report is content-free; the rejected content stays in private temporary storage and its authenticated account-actor record.'
  };
  mkdirSync('deliveries', { recursive: true });
  const path = 'deliveries/recipes-paid-diagnostic-129ba717.json';
  immutable(path, Buffer.from(JSON.stringify(report, null, 2) + '\n'));
  console.log(JSON.stringify({ report: path, ...report }, null, 2));
}
async function main() {
  fact(process.argv.length === 3 && ['--export', '--review'].includes(process.argv[2]), 'explicit_export_or_local_review_required');
  if (process.argv[2] === '--export') await exportRecord(); else review();
}
main().catch(error => { console.error(JSON.stringify({ status: 'unconfirmed', reason: error instanceof Error && /^[a-z_]+$/.test(error.message) ? error.message : 'scoped_evidence_review_unavailable', taskID, credentialsPrinted: false })); process.exitCode = 2; });
