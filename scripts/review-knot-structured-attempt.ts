// Exact November 14 aborted structured-recipes attempt. LOCAL evidence only.
// No API requests, task resume, execution, paid review or capture replay.
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash } from 'node:crypto';
import { AcceptanceSkillProvenance, assertAcceptanceIdentity } from './knot-acceptance-provenance';
const accountID = 'e00a9064-5f85-40bb-9f44-8bd60f90d24a', workspaceID = 'whisper-' + accountID;
const taskID = '19623939-62a4-4efc-b3b7-19e74b786840', conversationID = '73f4ed57-0378-47ac-a9d8-a081bd53a1dd', sourceMessageID = 'c68c4033-1fa8-43bd-bca4-94e79b5746b2';
const expectedBuild = '4110da0a37d66d75739d13632f97aac39d1f47380a504eaaa2e0c1c5a064d8a4';
const base = join(tmpdir(), 'knot-acceptance-uf26aun6d49w1tsjsm2u9');
const root = join(base, 'battery-2026-11-14T04-22-25-789Z', 'recipe-pdf');
const prior = join(base, 'battery-2026-11-14T03-41-24-088Z', 'recipe-pdf');
const loadAt = (directory: string, name: string): any => JSON.parse(readFileSync(join(directory, name), 'utf8'));
const load = (name: string) => loadAt(root, name);
const hash = (value: string | Uint8Array) => createHash('sha256').update(value).digest('hex');
function fact(value: unknown, reason: string): asserts value { if (!value) throw new Error(reason); }
function main() {
  fact(process.argv.length === 3 && process.argv[2] === '--review', 'explicit_local_review_required');
  const result = load('result.json'), intent = load('intent.json'), once = loadAt(base, 'recipes-structured-run-once-intent.json');
  const plan = loadAt(base, 'structured-latency-plan.json'), setup = loadAt(base, 'setup.json');
  const turn = { requestID: taskID, conversationID, sourceMessageID };
  for (const item of [result, intent]) fact(item.taskID === taskID && item.requestID === taskID && item.conversationID === conversationID && item.sourceMessageID === sourceMessageID && item.accountID === accountID && item.workspaceID === workspaceID, 'attempt_identity');
  fact(once.directory === join(root, '..') && once.accountID === accountID && once.expectedBuild === expectedBuild && intent.taskModelConsentVersion === 'knot_task_models_v1', 'once_scope');
  fact(setup.managedAuthentication === 'passed' && setup.sidecarDiscovery === 'passed' && setup.servingBuilds['/knot/shell/events'].worker === expectedBuild && setup.servingBuilds['/knot/shell/events'].actor === expectedBuild && Date.parse(setup.observedAt) < Date.parse(intent.startedAt), 'preflight_build');
  fact(!result.completed && !result.workIncomplete && result.issue === 'cached_skill_provenance_unconfirmed' && result.stopConfirmed && result.documents.length === 0 && result.executions.length === 2 && result.servingBuilds.worker === expectedBuild, 'aborted_result');
  fact(plan.referenceTaskID === 'b936a45f-b94a-4c5c-8ac6-b0c92e894466' && plan.targetMs === 330000 && plan.prospectivePlanningMs === 265225 && Date.parse(plan.declaredAt) < Date.parse(intent.startedAt), 'prospective_plan');
  const frames = readFileSync(join(root, 'frames.jsonl'), 'utf8').trim().split('\n').map(value => JSON.parse(value));
  fact(frames.length === result.frameCount && frames.every((frame: any, index: number) => frame.requestID === taskID && frame.sequence === index + 1), 'frame_sequence');
  fact(!frames.some((frame: any) => frame.type === 'complete' || /document_program|model_transport|document_content|document_review/.test(frame.activity?.kind ?? '')), 'no_document_generation_observed');
  const events = load('events.json');
  fact(events.records.length === 3 && events.documents.length === 0 && events.activities.some((event: any) => event.kind === 'cancelled' && event.taskID === taskID), 'cancelled_owned_turn');
  fact(events.records.every((record: any) => record.taskID === taskID && record.sourceMessageID === sourceMessageID && record.spec.conversationID === conversationID && record.workCommands === 0 && record.state === 'finished'), 'terminal_read_only_records');
  const commands = result.executions.map((execution: any) => {
    const id = execution.proposalID, proposal = load(id + '-proposal.json'), receipt = load(id + '-result.json'), log = load(id + '-log.json');
    assertAcceptanceIdentity(proposal, receipt, turn);
    const boundary = receipt.commandReceipt;
    fact(['memory_read', 'skill_index'].includes(execution.operation) && proposal.operation === execution.operation && receipt.status === 'completed' && receipt.exitCode === 0 && receipt.terminationConfirmed && receipt.outputComplete && !receipt.truncated && !receipt.contextTruncated && !receipt.cachedData && boundary?.source === 'harness_shell_boundaries_v1' && boundary.proposal_id === id && boundary.session_id === receipt.sessionID && boundary.exit_code === 0 && boundary.background_jobs === false && hash(receipt.stdout) === execution.stdoutSHA256, 'command_completion');
    fact(log.session_id === receipt.sessionID && log.stdout_from === 0 && log.stderr_from === 0 && !log.truncated && receipt.providerReceipt?.user_id === workspaceID && receipt.providerReceipt.session_id === receipt.sessionID, 'command_session');
    for (const stream of ['stdout', 'stderr']) {
      const bytes = Buffer.from(log[stream], 'utf8'), start = boundary[stream + '_start'], end = boundary[stream + '_end'];
      fact(Number.isSafeInteger(start) && Number.isSafeInteger(end) && start >= 0 && end >= start && end <= bytes.length && bytes.subarray(start, end).equals(Buffer.from(receipt[stream], 'utf8')), 'command_exact_log_boundaries');
    }
    return { proposalID: id, operation: execution.operation, sessionID: receipt.sessionID, commandSHA256: hash(proposal.command), stdoutSHA256: hash(receipt.stdout), logBoundariesMatch: true };
  });
  const cachedID = 'c04ed3bb-1246-48c0-b44d-befb0abccf4d', originalID = '9924aed8-6462-4db0-a779-a0f0400495b0';
  const proposal = load(cachedID + '-proposal.json'), cached = load(cachedID + '-execute.json'), stop = load(cachedID + '-stop.json');
  const originalProposal = loadAt(prior, originalID + '-proposal.json'), original = loadAt(prior, originalID + '-result.json');
  const provenance = new AcceptanceSkillProvenance({ accountID, workspaceID });
  provenance.remember(originalProposal, original, { requestID: 'b936a45f-b94a-4c5c-8ac6-b0c92e894466', conversationID: 'f5fa4af7-6299-4fd6-83f7-1275112879d9', sourceMessageID: 'b7b7d40a-75da-4e3f-ae51-08178aa6e5f5' });
  fact(provenance.acceptCache(proposal, cached, turn), 'cache_original_match');
  assertAcceptanceIdentity(proposal, stop, turn);
  fact(stop.status === 'completed' && stop.terminationConfirmed && stop.cachedData?.newExecution === false && !stop.commandReceipt && !stop.providerReceipt && stop.cachedData.sourceProposalID === originalID && stop.stdout === cached.stdout && stop.stderr === cached.stderr, 'no_cached_command_dispatch');
  const snapshot = {
    title: 'Structured recipes measurement — stopped before authoring', taskID, conversationID, sourceMessageID,
    sourceBuildSHA256: expectedBuild, preflightObservedAt: setup.observedAt,
    startedAt: result.startedAt, endedAt: result.endedAt,
    outcome: 'measurement_incomplete_harness_provenance_seed_missing',
    attemptTimings: { streamEndedMs: result.streamEndedMs, evidenceCollectionMs: result.evidenceCollectionMs, totalElapsedMs: result.elapsedMs, completionReceivedMs: null, captureElapsedMs: null },
    prospectivePlan: plan,
    comparison: { baselineCompletionMs: 603097, targetMs: 330000, targetAssessed: false, improvementEstablished: false, recalibratedFloorMs: null, reason: 'No authoring, document build, proof, content verdict or capture was reached. Abort duration is not document latency.' },
    commands,
    cache: { proposalID: cachedID, sourceProposalID: originalID, actualSessionID: cached.sessionID, sha256: cached.cachedData.sha256, originalObservedAt: cached.cachedData.observedAt, independentlyMatchedToKnownOriginalLocally: true, newShellExecution: false, initiallyImportedOriginalsOmittedThisReceipt: true },
    evidence: { observedOwnedProposals: 3, actualShellInputs: 2, cachedReads: 1, meteredWorkCommands: 0, observedAuthorResponses: 0, capturedDocuments: 0, ownedTurnCancellationRecorded: true, allObservedShellInputsTerminal: true, priorSessionReused: true },
    validation: { affectedBackendStrictTypes: 'passed', fullBackend: '14 current / 14 inherited; no additions; not globally clean', supportedWebChecks: 'passed; zero errors', newUnitOrRegressionTests: 'not run', runtimeDocumentPipeline: 'not reached', browserAndDeviceAcceptance: 'not performed' },
    scope: 'Local postmortem only; no remote call, task resume, paid review, command or capture replay. Once-intent remains consumed. One replacement fresh run requires explicit new authorization. Existing delivered files remain unchanged.'
  };
  const path = 'deliveries/recipes-structured-attempt-19623939.json';
  const bytes = Buffer.from(JSON.stringify(snapshot, null, 2) + '\n');
  mkdirSync('deliveries', { recursive: true });
  if (existsSync(path)) fact(readFileSync(path).equals(bytes), 'immutable_report_collision');
  else writeFileSync(path, bytes, { flag: 'wx' });
  console.log(JSON.stringify({ report: path, ...snapshot }, null, 2));
}
try { main(); } catch (error) { console.error(JSON.stringify({ status: 'unconfirmed', reason: error instanceof Error && /^[a-z_]+$/.test(error.message) ? error.message : 'local_review_unavailable', remoteCallsPerformed: false })); process.exitCode = 2; }
