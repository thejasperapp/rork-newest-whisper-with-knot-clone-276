// Exact November 14 replacement measurement: LOCAL retained evidence only.
// Never calls an API, submits/resumes work, runs a review or replays a capture.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash } from 'node:crypto';
import { AcceptanceSkillProvenance, assertAcceptanceIdentity } from './knot-acceptance-provenance';
import { structuredDocumentSchema } from '../functions/knot-document-structured';
const accountID = 'e00a9064-5f85-40bb-9f44-8bd60f90d24a', workspaceID = 'whisper-' + accountID;
const taskID = '0f1801ec-e34e-4cf7-8b4f-3b3aeb81ecd3', conversationID = 'b87a7a4d-d2ed-4408-8e42-f4cf2f743e58', sourceMessageID = '57afd4b7-f9b6-47ec-b92b-da0b74938f0f';
const sessionID = 'cfa2086e-cd18-45df-9025-e75ba8568225', programID = '915125c1-48b3-4532-b2b3-7af8307d7673';
const expectedBuild = '4110da0a37d66d75739d13632f97aac39d1f47380a504eaaa2e0c1c5a064d8a4';
const base = join(tmpdir(), 'knot-acceptance-uf26aun6d49w1tsjsm2u9');
const root = join(base, 'battery-2026-11-14T04-29-24-706Z', 'recipe-pdf');
const prior = join(base, 'battery-2026-11-14T03-41-24-088Z', 'recipe-pdf');
const loadAt = (directory: string, name: string): any => JSON.parse(readFileSync(join(directory, name), 'utf8'));
const load = (name: string) => loadAt(root, name);
const hash = (value: string | Uint8Array) => createHash('sha256').update(value).digest('hex');
function fact(value: unknown, reason: string): asserts value { if (!value) throw new Error(reason); }
function main() {
  fact(process.argv.length === 3 && process.argv[2] === '--review', 'explicit_local_review_required');
  const result = load('result.json'), intent = load('intent.json'), once = loadAt(base, 'recipes-structured-replacement-once-intent.json');
  const oldOnce = loadAt(base, 'recipes-structured-run-once-intent.json');
  const plan = loadAt(base, 'structured-latency-plan.json'), setup = loadAt(base, 'setup-structured-replacement.json');
  const baseline = loadAt(prior, 'result.json');
  const turn = { requestID: taskID, conversationID, sourceMessageID };
  for (const item of [result, intent]) fact(item.taskID === taskID && item.requestID === taskID && item.conversationID === conversationID && item.sourceMessageID === sourceMessageID && item.accountID === accountID && item.workspaceID === workspaceID, 'attempt_identity');
  fact(once.directory === join(root, '..') && once.accountID === accountID && once.workspaceID === workspaceID && once.expectedBuild === expectedBuild && once.backend === 'https://uf26aun6d49w1tsjsm2u9-backend.rork.app' && once.authorization === 'explicit_user_yes_one_replacement_fresh_measurement' && once.replacesAbortedTaskID === '19623939-62a4-4efc-b3b7-19e74b786840' && once.noAutomaticRetry && once.oldIntentPreserved && once.selectedKeys.length === 1 && once.selectedKeys[0] === 'recipe-pdf' && once.taskModelConsentVersion === 'knot_task_models_v1' && intent.taskModelConsentVersion === once.taskModelConsentVersion, 'exclusive_replacement_scope');
  fact(oldOnce.directory === join(base, 'battery-2026-11-14T04-22-25-789Z') && oldOnce.noAutomaticRetry && loadAt(base, 'setup.json').observedAt === '2026-11-14T04:22:20.380Z', 'original_scope_preserved');
  fact(setup.accountID === accountID && setup.managedAuthentication === 'passed' && setup.sidecarDiscovery === 'passed' && setup.servingBuilds['/knot/shell/events'].worker === expectedBuild && setup.servingBuilds['/knot/shell/events'].actor === expectedBuild && Date.parse(setup.observedAt) < Date.parse(intent.startedAt) && Date.parse(intent.startedAt) - Date.parse(setup.observedAt) < 300000, 'canonical_preflight');
  fact(result.completed && result.workIncomplete && result.issue === 'document_program_invalid' && result.stopConfirmed && result.documents.length === 0 && result.executions.length === 4 && result.servingBuilds.worker === expectedBuild && result.reply === '', 'failed_document_result');
  fact(baseline.taskID === 'b936a45f-b94a-4c5c-8ac6-b0c92e894466' && baseline.completionReceivedMs === 603097 && baseline.completed && !baseline.issue && loadAt(prior, 'intent.json').ask === intent.ask && plan.referenceTaskID === baseline.taskID && plan.targetMs === 330000 && plan.prospectivePlanningMs === 265225 && Date.parse(plan.declaredAt) < Date.parse(intent.startedAt), 'same_ask_and_prospective_plan');
  const frames = readFileSync(join(root, 'frames.jsonl'), 'utf8').trim().split('\n').map(value => JSON.parse(value));
  fact(frames.length === 35 && frames.length === result.frameCount && frames.every((frame: any, index: number) => frame.requestID === taskID && frame.sequence === index + 1 && (!frame.activity || frame.activity.taskID === taskID && frame.activity.sourceMessageID === sourceMessageID)), 'ordered_owned_frames');
  const completion = frames.find((frame: any) => frame.type === 'complete');
  fact(completion?.workIncomplete === true && completion.clientElapsedMs === result.completionReceivedMs && result.completionReceivedMs === 270443 && result.elapsedMs === 274464 && !result.captureElapsedMs && Date.parse(result.endedAt) - Date.parse(result.startedAt) === result.elapsedMs, 'failure_timing');
  const events = load('events.json');
  fact(events.records.length === 4 && events.documents.length === 0 && events.records.every((record: any) => record.taskID === taskID && record.sourceMessageID === sourceMessageID && record.spec.conversationID === conversationID && record.state === 'finished' && record.workCommands === 0 && record.workCost === 0), 'terminal_plumbing_only');
  fact(!events.activities.some((event: any) => /document_captured|document_content_check|document_visual_review/.test(event.kind)), 'no_final_quality_or_capture');
  const originalID = '9924aed8-6462-4db0-a779-a0f0400495b0';
  const provenance = new AcceptanceSkillProvenance({ accountID, workspaceID });
  provenance.remember(loadAt(prior, originalID + '-proposal.json'), loadAt(prior, originalID + '-result.json'), { requestID: baseline.requestID, conversationID: baseline.conversationID, sourceMessageID: baseline.sourceMessageID });
  const commands = result.executions.map((execution: any) => {
    const id = execution.proposalID, proposal = load(id + '-proposal.json'), receipt = load(id + '-result.json');
    assertAcceptanceIdentity(proposal, receipt, turn);
    fact(proposal.operation === execution.operation && receipt.status === 'completed' && receipt.exitCode === 0 && receipt.terminationConfirmed && receipt.outputComplete && !receipt.truncated && !receipt.contextTruncated && receipt.sessionID === sessionID && hash(receipt.stdout) === execution.stdoutSHA256, 'complete_owned_receipt');
    if (receipt.cachedData) {
      fact(id === 'dbfd9ad1-a036-45ab-aaf2-8f10badccd77' && provenance.acceptCache(proposal, receipt, turn) && receipt.cachedData.sourceProposalID === originalID, 'strict_known_original_cache');
      return { proposalID: id, operation: execution.operation, sessionID, commandSHA256: hash(proposal.command), stdoutSHA256: hash(receipt.stdout), newShellExecution: false, cachedSourceProposalID: originalID, cacheMatchesCompleteOriginal: true };
    }
    const log = load(id + '-log.json'), boundary = receipt.commandReceipt;
    fact(['memory_read', 'skill_index', 'workspace_inventory'].includes(execution.operation) && boundary?.source === 'harness_shell_boundaries_v1' && boundary.proposal_id === id && boundary.session_id === sessionID && boundary.exit_code === 0 && boundary.background_jobs === false && log.session_id === sessionID && log.stdout_from === 0 && log.stderr_from === 0 && !log.truncated && receipt.providerReceipt?.user_id === workspaceID && receipt.providerReceipt.session_id === sessionID && receipt.providerReceipt.output_complete === true && receipt.providerReceipt.output_late_bytes === 0, 'command_and_provider_boundary');
    for (const stream of ['stdout', 'stderr']) {
      const bytes = Buffer.from(log[stream], 'utf8'), start = boundary[stream + '_start'], end = boundary[stream + '_end'];
      fact(Number.isSafeInteger(start) && Number.isSafeInteger(end) && start >= 0 && end >= start && end <= bytes.length && bytes.subarray(start, end).equals(Buffer.from(receipt[stream], 'utf8')), 'exact_full_log_bytes');
    }
    return { proposalID: id, operation: execution.operation, sessionID, commandSHA256: hash(proposal.command), stdoutSHA256: hash(receipt.stdout), newShellExecution: true, logBoundariesMatch: true };
  });
  fact(commands.filter((entry: any) => entry.newShellExecution).length === 3, 'actual_shell_input_count');
  const activities = frames.filter((frame: any) => frame.activity).map((frame: any) => frame.activity);
  const attemptFrames = activities.filter((activity: any) => activity.kind === 'document_program_attempt');
  const transports = activities.filter((activity: any) => activity.kind === 'model_transport_outcome' && activity.detail?.stage === 'document_authoring');
  const validations = activities.filter((activity: any) => ['document_program_retry', 'tool_request_rejected'].includes(activity.kind) && activity.detail?.programID === programID);
  const stopped = activities.find((activity: any) => activity.kind === 'document_work_unavailable')?.detail;
  const schemaSHA256 = hash(JSON.stringify(structuredDocumentSchema));
  fact(schemaSHA256 === '8709e414481e63158fe11e61e2eb2407b38531aff44b22e40bed48eb86e7b4c9' && attemptFrames.length === 3 && transports.length === 3 && validations.length === 3 && stopped?.reason === 'document_program_invalid' && !stopped.sourceMeasured && !stopped.finalMeasured && !stopped.proofPrepared && !stopped.proofConfirmed && stopped.commands === 0 && stopped.commandLimit === 10000 && stopped.programBytes === 0 && stopped.sliceCount === 0 && stopped.programSHA256 === hash('') && stopped.modelResponseBytes === 47285 && stopped.authoringResponses === 3 && !activities.some((activity: any) => ['document_program_slice', 'document_program_sealed'].includes(activity.kind)), 'zero_sealed_or_executed_document_bytes');
  let previousResponseBytes = 0;
  const authoring = transports.map((transport: any, index: number) => {
    const detail = transport.detail, validation = validations[index].detail, attempt = attemptFrames[index].detail;
    fact(detail.model === 'anthropic/claude-sonnet-4.6' && detail.schemaHash === schemaSHA256 && detail.transportOutcome === 'recovered' && detail.transportCallCount === 1 && detail.transportAttempt === 1 && validation.check === 'slice_shape' && validation.attempt === index + 1 && validation.authoringResponses === index + 1 && validation.programBytes === 0 && attempt.sliceIndex === 0 && attempt.sliceCount === 0 && validation.sliceCount === 0 && validation.authoringTotalPromptBytes === detail.promptBytes + detail.promptSections.contractBytes && validation.authoringTotalPromptBytes === (index === 0 ? 46110 : 46238), 'authoring_attempt_binding');
    const modelResponseBytes = validation.modelResponseBytes - previousResponseBytes; previousResponseBytes = validation.modelResponseBytes;
    fact(modelResponseBytes > 0 && detail.transportElapsedMs > 0 && detail.transportChunkCount > 0, 'returned_response_metrics');
    return { attempt: index + 1, model: detail.model, schemaSHA256, returnedModelResponseBytes: modelResponseBytes, providerElapsedMs: detail.transportElapsedMs, returnedBytesPerProviderSecond: Math.round(modelResponseBytes * 100000 / detail.transportElapsedMs) / 100, firstContentMs: detail.transportFirstTokenMs, maxIdleMs: detail.transportMaxIdleMs, transportCalls: 1, contractOutcome: 'slice_shape_rejected', sealedProgramBytes: 0, storagePieces: 0, promptBytesIncludingContract: validation.authoringTotalPromptBytes, promptOverageBytes: validation.authoringPromptOverageBytes, completeReadMessageBytes: validation.authoringReadBytes };
  });
  const providerGenerationMs = authoring.reduce((sum: number, entry: any) => sum + entry.providerElapsedMs, 0);
  fact(providerGenerationMs === 255554 && previousResponseBytes === 47285, 'aggregate_generation_metrics');
  const report = {
    title: 'Structured recipes replacement measurement — authoring rejected', taskID, conversationID, sourceMessageID,
    sourceBuildSHA256: expectedBuild, preflightObservedAt: setup.observedAt, startedAt: result.startedAt, endedAt: result.endedAt,
    outcome: 'failed_before_source_build_proof_or_capture', prospectivePlan: plan,
    attemptTimings: { incompleteCompletionEventMs: result.completionReceivedMs, streamEndedMs: result.streamEndedMs, evidenceCollectionMs: result.evidenceCollectionMs, totalElapsedMs: result.elapsedMs, successfulCompletionMs: null, captureElapsedMs: null },
    comparison: { baselineTaskID: baseline.taskID, baselineCompletionMs: 603097, exactSameAsk: true, targetMs: 330000, targetMet: false, successfulLatencyComparisonAvailable: false, improvementEstablished: false, recalibratedSuccessfulPipelineFloorMs: null, reason: 'The 270443 ms event reports incomplete work, not PDF completion. No new PDF exists; failure duration cannot establish successful delivery latency or a new floor.' },
    authoring, providerGenerationMs, exposedReturnedModelResponseBytes: previousResponseBytes,
    aggregateReturnedBytesPerProviderSecond: Math.round(previousResponseBytes * 100000 / providerGenerationMs) / 100,
    nonProviderTimeThroughIncompleteCompletionMs: result.completionReceivedMs - providerGenerationMs,
    throughputScope: 'Returned exposed response-content bytes, including rejected responses; not accepted content, deterministic program throughput, renderer throughput or a successful-pipeline calibration. Internal discarded transport bodies, if any, are outside this metric.',
    commands,
    evidence: { observedOwnedProposals: 4, actualShellInputs: 3, strictKnownOriginalCachedReads: 1, samePreviouslyLiveSessionReused: true, meteredWorkCommands: 0, observedAuthorResponses: 3, observedAuthorProviderCalls: 3, sealedProgramBytes: 0, sourceBuildProofCommands: 0, contentChecks: 0, visualPageReviews: 0, localLayoutPatches: 0, captures: 0, finalPDFs: 0, noHistoricalReplay: true },
    diagnosis: { confirmedGate: 'document_authoring / slice_shape on each of three attempts', completeJSONParsingReached: true, exactRejectedField: 'unavailable in retained diagnostics', rawReturnedBodiesRetained: false, sourceBranchesCoveredByThisGate: ['Preparation interpreter/path or prefix/index constraint', 'Structured content validation or deterministic source construction', 'Returned executable-envelope validation'], exactRootCauseEstablished: false, providerOutageOrTimeoutEstablished: false, guideProvenanceProblemResolvedForThisRun: true, nextInvestigation: 'Add content-free field/path/code diagnostics at the distinct structured validation branches and verify the selected descriptor before spending another author response. Preserve strict content/integrity gates and full guidance; a further paid run requires fresh explicit permission.' },
    quality: { byteFidelity: 'not reached', sourceCoverage: 'not reached', finalContentCoverage: 'not reached', visualReview: 'not reached', nutritionCertification: false },
    validation: { replacementHarnessAndEvidenceReviewerStrictTypes: 'passed', deployedBackendSourceStamp: 'unchanged and verified', supportedWebStaticAndBuildChecks: 'passed; zero errors', fullBackend: '14 inherited diagnostics; no added signatures or counts in prior validation; not globally clean', newUnitOrRegressionTests: 'not run', backendRuntimeMeasurement: 'performed once; failed at authoring validation', browserDeviceAndExactOwnerSignedReleaseAcceptance: 'not performed' },
    scope: 'One explicitly authorized replacement fresh task only, using the existing dedicated owned session and original backend. Local evidence review never submits or resumes commands, model calls, reviews or captures. Both structured once-intents and all earlier deliveries remain preserved. No new PDF is claimed or substituted. Backend source is unchanged. No automatic retry or further paid measurement authorized.'
  };
  const path = 'deliveries/recipes-structured-replacement-0f1801ec.json';
  const bytes = Buffer.from(JSON.stringify(report, null, 2) + '\n');
  mkdirSync('deliveries', { recursive: true });
  if (existsSync(path)) fact(readFileSync(path).equals(bytes), 'immutable_report_collision');
  else writeFileSync(path, bytes, { flag: 'wx' });
  console.log(JSON.stringify({ report: path, ...report }, null, 2));
}
try { main(); } catch (error) { console.error(JSON.stringify({ status: 'unconfirmed', reason: error instanceof Error && /^[a-z_]+$/.test(error.message) ? error.message : 'local_review_unavailable', remoteCallsPerformed: false })); process.exitCode = 2; }
