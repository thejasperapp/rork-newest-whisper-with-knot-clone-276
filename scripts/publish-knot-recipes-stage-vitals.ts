// Recorded-evidence accounting only for the already delivered November 14 run.
// No credentials, network, provider calls, shell commands, reviews or capture replay.
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const mode = process.argv[2];
function fact(value: unknown, code: string): asserts value { if (!value) throw new Error(code); }
fact(process.argv.length === 3 && ['--inspect', '--publish'].includes(mode), 'explicit_mode_required');
const taskID = '8b14eaa8-9fbd-4295-bd36-7dc33d9e8635';
const root = join(tmpdir(), 'knot-acceptance-uf26aun6d49w1tsjsm2u9/battery-2026-11-14T06-48-38-813Z/recipe-pdf');
const load = (name: string): any => JSON.parse(readFileSync(join(root, name), 'utf8'));
const hash = (bytes: string | Uint8Array) => createHash('sha256').update(bytes).digest('hex');
const result = load('result.json');
const delivery = JSON.parse(readFileSync('deliveries/recipes-repair-8b14eaa8.json', 'utf8'));
const frameBytes = readFileSync(join(root, 'frames.jsonl'));
const frames: any[] = frameBytes.toString('utf8').trim().split('\n').map(line => JSON.parse(line));
const at = (ms: number) => new Date(ms).toISOString();
const activityAt = (frame: any) => Date.parse(frame.activity.recordedAt);
const sum = (values: number[]) => values.reduce((a, b) => a + b, 0);
const sec = (ms: number | null) => ms === null ? 'not retained' : (ms / 1000).toFixed(3) + ' s';
fact(result.taskID === taskID && delivery.taskID === taskID && result.completed && result.completionReceivedMs === 634211 && result.documents.length === 1 && frames.length === 110 && frames.every((frame, i) => frame.requestID === taskID && frame.sequence === i + 1), 'exact_completed_run');
fact(frames.find(frame => frame.type === 'complete')?.clientElapsedMs === result.completionReceivedMs, 'completion_clock');
const sources = delivery.commands.filter((entry: any) => entry.stage === 'source');
const builds = delivery.commands.filter((entry: any) => entry.stage === 'build');
const proofs = delivery.manifests.filter((entry: any) => entry.marker === 'KNOT_DOCUMENT_V1' && entry.value.proofs?.length === 8 && entry.value.verification?.allPageProofs === true);
const sealed = frames.filter(frame => frame.activity?.kind === 'document_program_sealed');
fact(sources.length === 5 && sealed.length === 5 && builds.length === 2 && proofs.length === 2, 'stage_counts');
const events: any[] = [];
const evidenceFiles: { path: string; sha256: string; bytes: number }[] = [];
for (const entry of delivery.commands) {
  const name = entry.proposalID + '-events.json';
  const bytes = readFileSync(join(root, name));
  evidenceFiles.push({ path: name, sha256: hash(bytes), bytes: bytes.length });
  for (const event of JSON.parse(bytes.toString('utf8')).events ?? []) {
    fact(event.proposalID === entry.proposalID, 'event_proposal_binding');
    events.push(event);
  }
}
fact(new Set(events.map(event => event.sequence)).size === events.length, 'unique_event_sequences');
events.sort((a, b) => a.sequence - b.sequence);
const sourceIndex = (id: string) => sources.findIndex((entry: any) => entry.proposalID === id);
const proofIndex = (id: string) => proofs.findIndex((entry: any) => entry.id === id);
const label = (id: string) => sourceIndex(id) >= 0 ? 'Source ' + (sourceIndex(id) + 1) : proofIndex(id) >= 0 ? ['Candidate PDF', 'Delivered PDF'][proofIndex(id)] : id;
const routingStart = frames.find(frame => frame.sequence === 3 && frame.activity?.kind === 'work_routing');
const routingEnd = frames.find(frame => frame.sequence === 4 && frame.activity?.kind === 'work_routing' && frame.creative === true);
fact(routingStart && routingEnd, 'classification_boundaries');
const classification = {
  stage: 'Initial work classification', model: 'openai/gpt-4o',
  modelBasis: 'Verified run source: runStep initializes routing model via knotTaskModel; routing always selects GPT-4o.',
  responseBytes: null, providerElapsedMs: null, promptBytes: null,
  startedAt: routingStart.activity.recordedAt, endedAt: routingEnd.activity.recordedAt,
  observedWindowMs: activityAt(routingEnd) - activityAt(routingStart),
  durationScope: 'Timestamp-derived enclosing classification/parsing/routing window, NOT exact provider duration.',
  missingTelemetry: 'No classification response bytes, exact request prompt size or provider duration were retained.',
  providerDispatch: 'established_by_successful_classification_and_following_fixed_briefing',
  transportCalls: 1, retries: 0, frameSequences: [routingStart.sequence, routingEnd.sequence],
  outcome: 'create_document_routed', briefingIsSeparateModelCall: false,
};
const authoring = sealed.map((frame, i) => {
  const d = frame.activity.detail;
  fact(d.transportCallCount === 1 && d.authoringResponses === 1 && d.attempt === 1 && d.modelResponseBytes === d.contentBytes, 'one_response_per_author_stage');
  const began = activityAt(frame) - d.authoringElapsedMs;
  const transportStart = frames.slice(0, frame.sequence - 1).filter(entry => entry.activity?.kind === 'model_transport_attempt' && entry.stage === 'document_authoring').at(-1);
  const transportEnd = frames.slice(0, frame.sequence - 1).filter(entry => entry.activity?.kind === 'model_transport_outcome' && entry.stage === 'document_authoring').at(-1);
  fact(transportStart && transportEnd && transportEnd.transportElapsedMs === d.transportElapsedMs && activityAt(transportStart) >= began && activityAt(transportEnd) <= activityAt(frame), 'author_transport_binding');
  return {
    stage: i < 4 ? 'Full author pass ' + (i + 1) : 'Layout-only patch', proposalID: sources[i].proposalID,
    model: d.model, modelResponseBytes: d.modelResponseBytes, programBytes: d.programBytes,
    storagePieces: d.sliceCount, semanticResponses: d.authoringResponses, transportCalls: d.transportCallCount,
    authoringElapsedMs: d.authoringElapsedMs, providerElapsedMs: d.transportElapsedMs,
    firstContentMs: d.transportFirstTokenMs, maxIdleMs: d.transportMaxIdleMs,
    bytesPerSecond: d.authoringBytesPerSecond, returnedContentBytesPerSecond: Number((d.modelResponseBytes * 1000 / d.transportElapsedMs).toFixed(3)),
    promptBytesIncludingContract: d.authoringTotalPromptBytes, promptOverageBytes: d.authoringPromptOverageBytes,
    basePromptBytes: d.authoringBasePromptBytes, readPayloadMessageBytes: d.authoringReadBytes,
    developedAuthorshipMessageBytes: d.authoringDevelopedBytes, descriptorMessageBytes: d.authoringDescriptorBytes,
    startedAt: at(began), endedAt: frame.activity.recordedAt, providerStartedAt: transportStart.activity.recordedAt,
    providerEndedAt: transportEnd.activity.recordedAt, frameSequence: frame.sequence,
    automaticRetries: 0, outcome: 'sealed_and_executed', fullDocumentResponse: i < 4,
  };
});
const selection = frames.filter(frame => frame.activity?.kind === 'tool_selection_attempt').map((frame, i) => {
  const next = frames.slice(frame.sequence).find(entry => entry.activity && ['document_program_started', 'shell_review_ready', 'complete'].includes(entry.activity.kind));
  fact(next, 'selection_end_boundary');
  const author = next.activity.kind === 'document_program_started' ? authoring.find(entry => Date.parse(entry.startedAt) >= activityAt(frame) && Date.parse(entry.startedAt) <= activityAt(next)) : undefined;
  const endedAt = author?.startedAt ?? next.activity.recordedAt;
  const attempts = frames.slice(frame.sequence, next.sequence - 1).filter(entry => entry.activity?.kind === 'model_transport_attempt' && entry.stage === 'tool_selection');
  fact(attempts.length === 1, 'selection_single_transport_attempt');
  return { stage: 'Selection ' + (i + 1), phase: frame.selectionPhase, model: frame.model,
    promptBytes: frame.promptBytes, responseBytes: null, providerElapsedMs: null,
    responseBytesMissingReason: 'Successful selection response bodies and response byte counts were not retained.',
    durationMissingReason: 'No successful selection completion/provider-duration event was emitted.',
    startedAt: frame.activity.recordedAt, windowEndedAt: endedAt,
    observedWindowMs: Date.parse(endedAt) - activityAt(frame),
    durationScope: 'Timestamp-derived enclosing selection/validation/preparation window, NOT exact provider duration.',
    transportAttempts: 1, observedRetries: 0, frameSequence: frame.sequence, endFrameSequence: next.sequence,
    outcome: next.activity.kind === 'complete' ? 'closing_choice_completed' : author ? 'author_descriptor_accepted' : 'build_descriptor_accepted' };
});
const contentChecks = events.filter(event => event.kind === 'document_content_check_attempt').map(event => ({
  stage: label(event.proposalID), proposalID: event.proposalID, operation: event.operation,
  attempt: event.attempt, retry: event.attempt - 1, model: event.model,
  durationMs: event.durationMs, outcome: event.outcome, responseBytes: event.responseBytes,
  contentBytes: event.contentBytes, httpStatus: event.httpStatus, finishReason: event.finishReason,
  failureStage: event.failureStage ?? null, validationCode: event.validationCode ?? null,
  itemIndex: event.itemIndex ?? null, reason: event.reason ?? null,
  startedAt: at(Date.parse(event.recordedAt) - event.durationMs), endedAt: event.recordedAt,
  eventSequence: event.sequence,
  durationScope: 'Measured complete check attempt: request, response read, JSON/schema/grounding validation; not isolated model computation.',
  timestampScope: 'End is retained Event time; start is derived by subtracting measured attempt duration, with reporting/clock skew possible.',
  pageCoverage: event.operation === 'final' ? { pages: [1, 2, 3, 4, 5, 6, 7, 8], scope: 'complete extracted document text; NOT separate per-page model calls or confirmed per-page content verdicts' } : { pages: null, scope: 'complete HTML source; not yet paginated' },
}));
const sourceVerdicts = events.filter(event => /^document_source_(blocked|checked)$/.test(event.kind) || event.check?.sourceProposalID).map(event => ({
  stage: label(event.proposalID), proposalID: event.proposalID, recordedAt: event.recordedAt,
  outcome: event.check.verdict, sourceSHA256: event.check.sourceSHA256, eventSequence: event.sequence,
  findings: event.check.findings ?? [], advisories: event.check.advisories ?? [],
  observations: event.check.observations ?? [], requestedItems: event.check.requestedItems ?? [],
}));
fact(sourceVerdicts.length === 5 && contentChecks.length === 11, 'every_source_and_final_content_attempt');
const visualChecks: any[] = [];
for (const [index, proof] of proofs.entries()) {
  const id = proof.id, relevant = events.filter(event => event.proposalID === id);
  const attempts = contentChecks.filter(entry => entry.proposalID === id);
  let previous = attempts[attempts.length - 1].endedAt;
  let nextPage = 1;
  for (const event of relevant.filter(event => event.kind === 'document_visual_pages_observed')) {
    fact(event.finalSHA256 === proof.value.sha256 && event.pages.every((page: any) => proof.value.proofs.some((p: any) => p.page === page.page && p.sha256 === page.sha256)), 'visual_page_hash_binding');
    visualChecks.push({ stage: index === 0 ? 'Candidate PDF' : 'Delivered PDF', proposalID: id,
      finalSHA256: proof.value.sha256, model: 'openai/gpt-4o', pages: event.pages,
      providerElapsedMs: null, responseBytes: null, startedAt: previous, endedAt: event.recordedAt,
      observedWindowMs: Date.parse(event.recordedAt) - Date.parse(previous),
      durationScope: 'Timestamp-derived inter-event window including PNG reads/hash checks/provider/validation/reporting; exact provider duration was not retained.',
      outcome: event.pages.some((page: any) => page.verdict === 'issues') ? 'issues' : 'pass',
      attempts: 1, retries: 0, providerDispatch: 'established_by_bound_returned_verdicts', eventSequence: event.sequence });
    previous = event.recordedAt;
    nextPage = Math.max(...event.pages.map((page: any) => page.page)) + 1;
  }
  const assessed = relevant.find(event => event.kind === 'document_visual_assessed');
  fact(assessed, 'visual_terminal_assessment');
  if (assessed.status === 'unavailable') {
    visualChecks.push({ stage: 'Delivered PDF', proposalID: id, finalSHA256: proof.value.sha256,
      model: 'openai/gpt-4o', pages: proof.value.proofs.filter((p: any) => p.page >= nextPage && p.page < nextPage + 2).map((p: any) => ({ page: p.page, sha256: p.sha256, verdict: 'unconfirmed', issues: [] })),
      providerElapsedMs: null, responseBytes: null, startedAt: previous, endedAt: assessed.recordedAt,
      observedWindowMs: Date.parse(assessed.recordedAt) - Date.parse(previous),
      durationScope: 'Timestamp-derived next-batch/failure window; no request-start, HTTP outcome, response body or exact provider duration was retained.',
      outcome: 'unavailable', attempts: 1, retries: 0, providerDispatch: 'not_retained_could_fail_during_page_read_or_request_or_response_validation',
      issue: assessed.issue, eventSequence: assessed.sequence,
      pagesNotReached: proof.value.proofs.filter((p: any) => p.page >= nextPage + 2).map((p: any) => p.page) });
  }
}
const commands = (delivery.commands as any[]).map((entry: any) => {
  const receiptName = entry.proposalID + '-result.json';
  const receiptBytes = readFileSync(join(root, receiptName));
  const receipt = JSON.parse(receiptBytes.toString('utf8'));
  evidenceFiles.push({ path: receiptName, sha256: hash(receiptBytes), bytes: receiptBytes.length });
  const boundary = receipt.commandReceipt;
  if (entry.newExecution) fact(Date.parse(boundary.observed_finished_at) - Date.parse(boundary.started_at) === receipt.durationMs, 'command_duration_binding');
  fact(receipt.proposalID === entry.proposalID && receipt.status === 'completed' && receipt.exitCode === 0 && receipt.terminationConfirmed && hash(receipt.stdout) === entry.stdoutSHA256, 'verified_command_receipt');
  return { proposalID: entry.proposalID, stage: entry.stage ?? (proofIndex(entry.proposalID) >= 0 ? 'independent_proof' : entry.operation),
    operation: entry.operation, newExecution: entry.newExecution, durationMs: entry.newExecution ? receipt.durationMs : null,
    startedAt: entry.newExecution ? boundary.started_at : null, endedAt: entry.newExecution ? boundary.observed_finished_at : null,
    durationSource: entry.newExecution ? receipt.durationSource : 'cached_guide_not_new_execution', outcome: 'exit_0_complete' };
});
const fullRewriteCauses = sourceVerdicts.slice(0, 3).map((entry, i) => ({ fromPass: i + 1, toPass: i + 2,
  sourceProposalID: entry.proposalID, eventSequence: entry.eventSequence, recordedAt: entry.recordedAt,
  recordedSourceVerdict: entry.outcome, findings: entry.findings, observations: entry.observations,
  explanation: [
    'Source 1 was blocked solely by a requested_design_inadequate finding demanding a finalized polished PDF before the source was built. The next selection authored a new complete source.',
    'Source 2 was blocked after one unusable check and one issues verdict. Findings included judging design unavailable in HTML and missing recipe-specific fat-loss explanations. The next selection authored a new complete source.',
    'Source 3 was blocked after one unusable check and one issues verdict. Findings demanded individualized calorie/protein explanations and an editorial-layout outline. The next selection authored a new complete source.',
  ][i], automaticAuthorRetry: false }));
const providerGenerationMs = sum(authoring.map(entry => entry.providerElapsedMs));
const sourceContentMs = sum(contentChecks.filter(entry => entry.operation === 'source').map(entry => entry.durationMs));
const finalContentMs = sum(contentChecks.filter(entry => entry.operation === 'final').map(entry => entry.durationMs));
const visualWindowsMs = sum(visualChecks.map(entry => entry.observedWindowMs));
const selectionWindowsMs = sum(selection.map(entry => entry.observedWindowMs));
const commandMs = sum(commands.filter(entry => entry.newExecution).map(entry => entry.durationMs));
const authorStageMs = sum(authoring.map(entry => entry.authoringElapsedMs));
const stageIntervals = [
  { stage: classification.stage, start: Date.parse(classification.startedAt), end: Date.parse(classification.endedAt) },
  ...authoring.map(entry => ({ stage: entry.stage, start: Date.parse(entry.startedAt), end: Date.parse(entry.endedAt) })),
  ...selection.map(entry => ({ stage: entry.stage, start: Date.parse(entry.startedAt), end: Date.parse(entry.windowEndedAt) })),
  ...contentChecks.map(entry => ({ stage: entry.stage + ' content ' + entry.attempt, start: Date.parse(entry.startedAt), end: Date.parse(entry.endedAt) })),
  ...visualChecks.map(entry => ({ stage: entry.stage + ' visual ' + entry.pages.map((p: any) => p.page).join(','), start: Date.parse(entry.startedAt), end: Date.parse(entry.endedAt) })),
  ...commands.filter(entry => entry.newExecution).map(entry => ({ stage: entry.stage + ' ' + entry.proposalID, start: Date.parse(entry.startedAt), end: Date.parse(entry.endedAt) })),
].sort((a, b) => a.start - b.start || a.end - b.end);
const observedOverlaps: { earlier: string; later: string; overlapMs: number }[] = [];
for (let i = 0; i < stageIntervals.length; i++) {
  const current = stageIntervals[i];
  fact(Number.isFinite(current.start) && Number.isFinite(current.end) && current.end >= current.start, 'valid_stage_interval');
  for (const previous of stageIntervals.slice(0, i)) if (previous.end > current.start) {
    observedOverlaps.push({ earlier: previous.stage, later: current.stage, overlapMs: Math.min(previous.end, current.end) - current.start });
  }
}
fact(observedOverlaps.length === 0, 'nonoverlapping_recorded_stage_windows');
const knownMs = classification.observedWindowMs + authorStageMs + selectionWindowsMs + sourceContentMs + finalContentMs + visualWindowsMs + commandMs;
const residualMs = result.completionReceivedMs - knownMs;
fact(residualMs >= 0 && providerGenerationMs === 442096, 'nonnegative_accounting');
const longest = [{ stage: classification.stage, durationMs: classification.observedWindowMs, scope: classification.durationScope }, ...authoring.map(entry => ({ stage: entry.stage, durationMs: entry.authoringElapsedMs, scope: 'measured complete authoring stage', providerElapsedMs: entry.providerElapsedMs, proposalID: entry.proposalID })),
  ...selection.map(entry => ({ stage: entry.stage, durationMs: entry.observedWindowMs, scope: entry.durationScope })),
  ...contentChecks.map(entry => ({ stage: entry.stage + ' content attempt ' + entry.attempt, durationMs: entry.durationMs, scope: 'measured check attempt' })),
  ...visualChecks.map(entry => ({ stage: entry.stage + ' visual pages ' + entry.pages.map((p: any) => p.page).join(','), durationMs: entry.observedWindowMs, scope: entry.durationScope })),
  ...commands.filter(entry => entry.newExecution).map(entry => ({ stage: entry.stage, durationMs: entry.durationMs, scope: entry.durationSource }))].sort((a, b) => b.durationMs - a.durationMs)[0];
const checkGroups = [...new Set(contentChecks.map(entry => entry.proposalID))].map(id => {
  const group = contentChecks.filter(entry => entry.proposalID === id);
  fact(group.length <= 2 && group.every((entry, i) => entry.attempt === i + 1), 'two_attempt_content_limit');
  return { stage: label(id), proposalID: id, attempts: group.length, retries: group.length - 1,
    durationMs: sum(group.map(entry => entry.durationMs)), terminalOutcome: group[group.length - 1].outcome,
    unconfirmedAfterTwo: group.length === 2 && group[1].outcome === 'unconfirmed' };
});
const report = {
  title: 'Structured recipes — complete recorded stage vitals', taskID,
  conversationID: result.conversationID, sourceMessageID: result.sourceMessageID,
  scope: delivery.scope, sourceBuildSHA256: delivery.sourceBuildSHA256,
  startedAt: result.startedAt, endedAt: result.endedAt,
  timings: { captureElapsedMs: result.captureElapsedMs, completionReceivedMs: result.completionReceivedMs,
    streamEndedMs: result.streamEndedMs, evidenceCollectionMs: result.evidenceCollectionMs, totalElapsedMs: result.elapsedMs },
  comparison: { baselineCompletionMs: 603097, prospectivePlanningMs: 265225, targetMs: 330000,
    abovePlanningMs: result.completionReceivedMs - 265225, aboveTargetMs: result.completionReceivedMs - 330000,
    abovePriorCompletionMs: result.completionReceivedMs - 603097, speedImprovementEstablished: false,
    estimatedOneResponseGenerationMs: 102210, actualAuthorProviderMs: providerGenerationMs,
    generationAbovePlanMs: providerGenerationMs - 102210,
    plannedOtherMs: 163015, actualOtherThanAuthorProviderMs: result.completionReceivedMs - providerGenerationMs,
    otherAbovePlanMs: result.completionReceivedMs - providerGenerationMs - 163015,
    additionalFullPasses2Through4ProviderMs: sum(authoring.slice(1, 4).map(entry => entry.providerElapsedMs)) },
  authoring, providerGenerationMs, classification, selection,
  modelCalls: { classification: 1, authors: authoring.length, selections: selection.length,
    contentChecks: contentChecks.length, confirmedVisualBatches: visualChecks.filter(entry => entry.outcome !== 'unavailable').length,
    confirmedTotal: 1 + authoring.length + selection.length + contentChecks.length + visualChecks.filter(entry => entry.outcome !== 'unavailable').length,
    additionalPossibleVisualRequest: 1, additionalPossibleVisualDispatchConfirmed: false,
    briefing: 'Fixed text, not an additional generation',
    providerGenerationMsScope: 'Author provider time only; excludes content-check attempts (accounted separately) and classification/selection/visual calls (exact provider timing unavailable).' },
  contentChecks, sourceVerdicts, visualChecks, commands, fullRewriteCauses,
  longestStage: longest,
  accounting: { basis: 'Completion-received clock. Author/provider times nested, never added to each other. Classification, visual and selection windows include non-provider work; they are not exact model timings.',
    authoringStagesMs: authorStageMs, authorProviderMs: providerGenerationMs, authorWrapperMs: authorStageMs - providerGenerationMs,
    classificationEnclosingWindowMs: classification.observedWindowMs,
    selectionEnclosingWindowsMs: selectionWindowsMs, sourceContentChecksMs: sourceContentMs,
    finalContentChecksMs: finalContentMs, visualEnclosingWindowsMs: visualWindowsMs,
    actualForegroundCommandObservationMs: commandMs, residualOrchestrationNetworkAndCaptureMs: residualMs,
    sumMs: knownMs + residualMs, percentCompletionInAuthorProvider: Number((providerGenerationMs * 100 / result.completionReceivedMs).toFixed(3)),
    residualMeaning: 'Arithmetic remainder, not an independently measured stage or provider cost. Includes auth, routing outside the classification window, tool/API handoffs, source/final reads outside visual windows, persistence/capture, SSE/network scheduling. Cross-clock timestamps have small observation skew.',
    observedStageIntervalCount: stageIntervals.length, observedOverlaps,
    exactCallTimingCoverageComplete: false },
  retryCounts: { automaticAuthorValidationOrTransportRetries: 0, sourceAndFinalCheckGroups: checkGroups,
    contentCalls: contentChecks.length, contentRetries: sum(checkGroups.map(entry => entry.retries)),
    visualCompletedBatches: visualChecks.filter(entry => entry.outcome !== 'unavailable').length,
    visualAbortedNextBatchWindows: visualChecks.filter(entry => entry.outcome === 'unavailable').length,
    visualRetries: 0, selectionObservedRetries: sum(selection.map(entry => entry.observedRetries)),
    rule: 'At most two content attempts per exact source/final; still unconfirmed after two degrades and records. Distinct revised bytes are separately identified check groups. Visual batches have no retry loop.',
    finalContentDegradedAfterTwoForBothPDFs: checkGroups.filter(entry => entry.stage.endsWith('PDF')).every(entry => entry.unconfirmedAfterTwo) },
  quality: { byteFidelity: 'pass', finalContentCoverage: 'unconfirmed', visualReview: 'unavailable',
    candidateVisualPagesReviewed: [1, 2, 3, 4, 5, 6, 7, 8], finalVisualPagesConfirmed: [1, 2],
    finalVisualPagesUnconfirmed: [3, 4], finalVisualPagesNotReached: [5, 6, 7, 8],
    certified: false, factualOrNutritionCertification: false },
  evidence: { orderedFrames: frames.length, contentAttemptEvents: contentChecks.length,
    commandReceipts: commands.length, actualNewExecutions: commands.filter(entry => entry.newExecution).length,
    cachedOriginalBoundGuide: commands.filter(entry => !entry.newExecution).length,
    framesSHA256: hash(frameBytes), files: evidenceFiles,
    originalReport: 'deliveries/recipes-repair-8b14eaa8.json',
    originalPDF: delivery.delivery.path, originalPDFSHA256: delivery.delivery.sha256,
    newProviderCalls: 0, newRemoteCommands: 0, historicalReplay: false,
    aiLogLookup: 'Exact source-message scoped rork AI log lookup returned no logs.' },
  limitations: [
    'The initial GPT-4o classification is a separate model call: only its 1147 ms enclosing window is retained, not response bytes or exact provider duration. The following briefing is fixed text, not another generation.',
    'No exact visual provider durations or response byte counts were retained. Every available page verdict and timestamp-bounded batch/failure window is included instead.',
    'Successful selection response byte counts and exact provider elapsed times were not retained. All observed selection starts and enclosing windows are included; missing is not zero.',
    'Delivered-PDF visual failure has only document_visual_review_unavailable; dispatch/HTTP/parser/uncertainty cause cannot be recovered. Pages 3–4 identify the next loop batch, not proof of provider submission.',
    'Content checks compare complete source/extracted text, not separate per-page calls. Neither failed final-content attempt confirms individual page coverage.',
    'Raw checker responses were not retained; the recorded grounding diagnostics are not sufficient to recover the rejected literal quote.',
    'Earlier delivered reports/PDFs remain unchanged. No new paid task, re-review, capture, deployment or device/browser interaction is performed for this accounting.',
  ],
};
if (mode === '--inspect') {
  console.log(JSON.stringify({ ...report, evidence: { ...report.evidence, files: report.evidence.files.map(file => file.path) } }, null, 2));
} else {
  const jsonPath = 'deliveries/recipes-stage-vitals-8b14eaa8.json';
  const tablePath = 'deliveries/recipes-stage-table-8b14eaa8.md';
  const cell = (value: unknown) => String(value ?? 'not retained').replaceAll('|', '\\|').replaceAll('\n', ' ');
  const table = (headers: string[], rows: unknown[][]) => ['| ' + headers.join(' | ') + ' |', '| ' + headers.map(() => '---').join(' | ') + ' |', ...rows.map(row => '| ' + row.map(cell).join(' | ') + ' |')].join('\n');
  const markdown = [
    '# Structured recipes — stage vitals',
    `Task: ${taskID}. Recorded run: ${result.startedAt} to ${result.endedAt}. All elapsed values below are seconds unless labeled otherwise.`,
    `**Completion: ${sec(result.completionReceivedMs)} (10m34.211s). Capture: ${sec(result.captureElapsedMs)}. Above the 265.225 s planning estimate: ${sec(report.comparison.abovePlanningMs)}; above the 330 s target: ${sec(report.comparison.aboveTargetMs)}.**`,
    `**Single longest stage: ${longest.stage}, ${sec(longest.durationMs)} complete authoring (${sec(authoring[3].providerElapsedMs)} provider). Author providers total ${sec(providerGenerationMs)}, ${report.accounting.percentCompletionInAuthorProvider}% of completion.**`,
    `Model calls: ${report.modelCalls.confirmedTotal} established (${report.modelCalls.classification} classification + ${authoring.length} author + ${selection.length} selection + ${contentChecks.length} content + ${report.modelCalls.confirmedVisualBatches} visual), plus one next-visual-batch failure window whose provider dispatch is unconfirmed. Author-provider totals below do not pretend to include the unmeasured classification/selection/visual provider times.`,
    '## Initial classification generation',
    'Model: openai/gpt-4o, selected by the verified routing policy. The work-routing event precedes the actual classification fetch; the next routing event is its successful fixed-text briefing. One classification call, no retry. The briefing itself is not another generation.',
    table(['Stage', 'Returned B', 'Exact provider elapsed', 'Enclosing window', 'Start UTC', 'End UTC', 'Outcome'], [[classification.stage, 'not retained', 'not retained', sec(classification.observedWindowMs), classification.startedAt, classification.endedAt, classification.outcome]]),
    '## Every author generation',
    'Returned bytes are the actual model content, not deterministic reconstructed program bytes. All five responses have one semantic response and one transport call, zero automatic retries. The fifth is a layout patch, not a full rewrite.',
    table(['Stage', 'Returned B', 'Program B', 'Provider elapsed', 'Total author elapsed', 'Prompt B incl. contract', 'Outcome'], authoring.map(entry => [entry.stage, entry.modelResponseBytes, entry.programBytes, sec(entry.providerElapsedMs), sec(entry.authoringElapsedMs), entry.promptBytesIncludingContract, entry.outcome])),
    'Model: anthropic/claude-sonnet-4.6. Prior vitals fields (storage pieces, first content, idle, prompt components and throughput) are preserved in the JSON companion. Program-byte throughput is not returned-content throughput, particularly for the 148-byte patch.',
    '## Every selection generation',
    '**Telemetry gap:** successful selection response bytes and exact provider durations were not retained. These are enclosing timestamp-derived selection/validation/preparation windows, NOT fabricated exact model timings. All are Sonnet 4.6, one observed transport attempt and zero observed retries.',
    table(['Stage', 'Purpose', 'Prompt B', 'Returned B', 'Exact provider elapsed', 'Enclosing window', 'Start UTC', 'End UTC'], selection.map(entry => [entry.stage, entry.phase, entry.promptBytes, 'not retained', 'not retained', sec(entry.observedWindowMs), entry.startedAt, entry.windowEndedAt])),
    '## Every content-check call',
    'Model: openai/gpt-4o. Source calls cover complete, unpaginated HTML. Each final call covers the complete extracted eight-page text in one request; there are no separate per-page content calls or independently confirmed per-page content verdicts. Every retained call returned HTTP 200 / finish=stop. Duration measures the request/response/validation attempt, not isolated model computation. JSON includes Event end time, duration-derived start and event identity.',
    'An issues result can coexist with an item-grounding diagnostic: the checker preserves separately literal-grounded blocking findings even when the requested-item coverage structure fails validation. That does not establish a coverage pass or recover the rejected coverage quote.',
    table(['Checked bytes', 'Attempt', 'Retry', 'Measured elapsed', 'Response B', 'Content B', 'Outcome', 'Diagnostic'], contentChecks.map(entry => [entry.stage, entry.attempt, entry.retry, sec(entry.durationMs), entry.responseBytes, entry.contentBytes, entry.outcome, [entry.failureStage, entry.validationCode, entry.itemIndex === null ? null : 'item ' + entry.itemIndex].filter(x => x !== null).join(' / ') || 'none'])),
    table(['Check group', 'Attempts', 'Retries', 'Total elapsed', 'Terminal outcome'], checkGroups.map(entry => [entry.stage, entry.attempts, entry.retries, sec(entry.durationMs), entry.terminalOutcome])),
    `Content totals: ${contentChecks.length} calls, ${report.retryCounts.contentRetries} retries across ${checkGroups.length} distinct source/final identities; ${sec(sourceContentMs + finalContentMs)}. Both PDFs stop after two unconfirmed final checks and record degradation; no minutes-long retry loop. Source 2 and source 3 stop their retry after an issues finding rather than a pass.`,
    '## Every visual batch and every page',
    '**Exact per-call provider durations and response bytes were not retained.** Model: openai/gpt-4o. Each row is one serial batch window, including PNG reads/hashes and response validation. Do not add a batch duration once per page. Page hashes and literal findings are retained in the JSON.',
    table(['PDF', 'Pages', 'Per-page outcome', 'Enclosing window', 'Exact provider elapsed', 'Retries', 'Window start UTC', 'Window end UTC'], visualChecks.map(entry => [entry.stage, entry.pages.map((p: any) => p.page).join(', '), entry.pages.map((p: any) => p.page + ': ' + p.verdict + (p.issues.length ? ' (' + p.issues.length + ' findings)' : '')).join('; '), sec(entry.observedWindowMs), 'not retained', entry.retries, entry.startedAt, entry.endedAt])),
    'Delivered pages 5, 6, 7, 8: not reached by visual review; no verdict, no call duration and no retry. Delivered pages 3–4: the next loop batch failed/unconfirmed within its recorded window; the generic failure does not establish that its provider request was dispatched. Candidate page outcomes do not certify the changed delivered PDF.',
    '### Literal candidate visual findings',
    ...visualChecks.filter(entry => entry.stage === 'Candidate PDF').flatMap(entry => entry.pages.flatMap((p: any) => p.issues.map((issue: string) => '- Page ' + p.page + ': ' + issue))),
    '## Why there were four full passes',
    ...fullRewriteCauses.flatMap(entry => [
      `### Full pass ${entry.fromPass} → ${entry.toPass}`,
      entry.explanation,
      ...entry.findings.map((finding: any) => `- ${finding.kind} — ${finding.item}: ${finding.detail} Repair: ${finding.repair}`),
    ]),
    'Full pass 4 receives a source pass and proceeds to build/proof. Its first rendered PDF then receives twelve visual findings across pages 3–6, causing the one 148-byte layout-only patch, followed by source check/build/proof of distinct final bytes. The final unconfirmed content checks did not trigger another full generation.',
    `Full passes 2–4 alone cost ${sec(report.comparison.additionalFullPasses2Through4ProviderMs)} of additional provider generation. The plan priced one complete response, not four. These are source-verdict-driven rewrites, not automatic author validation/transport retries. The source checker still demanded finished-PDF/editorial treatment before rendering; the earlier phase correction was not fully effective. Some recorded substantive explanation findings also contributed; this is not a claim that every objection was visual.`,
    '## Non-overlapping completion-clock accounting',
    'Nested provider and complete-author stage clocks are separated. Classification, selection and visual rows are enclosing windows, not exact provider durations. All recorded stage intervals are checked for overlap before publication. Foreground command observations cover execution only, not API handoff or surrounding checks. Residual is arithmetic, not an invented measured stage; small cross-clock observation skew is included in it.',
    table(['Category', 'Elapsed', 'Basis'], [
      ['Initial classification window', sec(classification.observedWindowMs), 'Timestamp-derived, exact provider unavailable'],
      ['Author stages (four full + patch)', sec(authorStageMs), 'Measured; includes ' + sec(providerGenerationMs) + ' provider + ' + sec(authorStageMs - providerGenerationMs) + ' wrapper'],
      ['Selection / closing windows', sec(selectionWindowsMs), 'Timestamp-derived, exact provider unavailable'],
      ['Source content checks', sec(sourceContentMs), 'Measured attempts'],
      ['Final content checks', sec(finalContentMs), 'Measured attempts'],
      ['Visual windows', sec(visualWindowsMs), 'Timestamp-derived including page I/O / validation'],
      ['Actual foreground commands', sec(commandMs), 'Harness observations; cached guide excluded'],
      ['Remaining routing, I/O, handoffs, capture, network', sec(residualMs), 'Arithmetic remainder'],
      ['Total to completion received', sec(knownMs + residualMs), 'Reconciles exactly to 634211 ms'],
    ]),
    `Planning reconciliation: ${sec(report.comparison.generationAbovePlanMs)} more author-provider time than the planned 102.210 s, plus ${sec(report.comparison.otherAbovePlanMs)} more other time than the planned 163.015 s, equals the full ${sec(report.comparison.abovePlanningMs)} overrun. No speed improvement is established.`,
    '## Every actual foreground command',
    table(['Operation', 'Proposal', 'Measured elapsed', 'New execution', 'Outcome'], commands.map(entry => [entry.stage, entry.proposalID, sec(entry.durationMs), entry.newExecution ? 'yes' : 'no — original-bound cached guide', entry.outcome])),
    '## Outcome and limits',
    'Actual immutable PDF: 36,646 bytes / 8 pages; SHA-256 ' + delivery.delivery.sha256 + '. Capture/build/proof/download bytes agree. Content remains unconfirmed and final visual review unavailable: delivery closed, quality acceptance did not pass.',
    ...report.limitations.map(text => '- ' + text),
    'Provenance: 110 ordered owned frames, 14 receipts (13 new executions + one original-bound cached guide), 11 exact content-attempt Events. Raw evidence hashes and every page/hash binding are in the JSON companion. Only retained records were analyzed; zero new provider calls, remote commands or replays.',
    'The JSON companion uses the established title/task identity/timings/authoring/providerGenerationMs/evidence/quality record envelope and preserves the earlier author-vitals field names. Original evidence reports are not overwritten.',
  ].join('\n\n') + '\n';
  function immutable(path: string, bytes: Buffer) {
    if (existsSync(path)) fact(readFileSync(path).equals(bytes), 'immutable_collision');
    else writeFileSync(path, bytes, { flag: 'wx' });
  }
  immutable(jsonPath, Buffer.from(JSON.stringify(report, null, 2) + '\n'));
  immutable(tablePath, Buffer.from(markdown));
  console.log(JSON.stringify({ jsonPath, tablePath, taskID, longestStage: longest, accounting: report.accounting, comparison: report.comparison, retryCounts: report.retryCounts }, null, 2));
}
