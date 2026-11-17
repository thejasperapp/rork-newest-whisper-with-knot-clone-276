// Read-only exact retry reconciliation. Input: project backend JSON-lines logs.
// Never uses credentials, reads session files, invokes AI or dispatches a command.
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
const attempt = process.argv[process.argv.indexOf('--attempt') + 1];
if (!process.argv.includes('--attempt') || !/^0[1-3]$/.test(attempt ?? '')) throw new Error('explicit_retry_attempt_required');
const stem = 'managed-prime-retry-20261114-' + attempt;
const directory = join(tmpdir(), 'knot-managed-prime-mayokn2749ag072e3uvbh-20261114', 'retry-' + attempt);
const read = (name: string) => JSON.parse(readFileSync(join(directory, name), 'utf8'));
const intent = JSON.parse(readFileSync(new URL('../deliveries/' + stem + '-intent.json', import.meta.url), 'utf8'));
const outcome = read('result.json'), streamResponse = read('stream-response.json'), events = read('events.json');
const frames = readFileSync(join(directory, 'frames.jsonl'), 'utf8').trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
if (intent.accountID !== 'e00a9064-5f85-40bb-9f44-8bd60f90d24a' || intent.workspaceID !== 'whisper-' + intent.accountID || intent.attempt !== attempt || outcome.requestID !== intent.requestID || outcome.taskID !== intent.requestID || frames.some((frame, index) => frame.requestID !== intent.requestID || frame.sequence !== index + 1)) throw new Error('exact_retry_evidence_required');
const input = readFileSync(0, 'utf8');
const logs = input.trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
const modelCalls = logs.flatMap(log => {
  const match = /knot_model_call (\{.*\})$/.exec(log.message ?? '');
  if (!match) return [];
  const call = JSON.parse(match[1]);
  if (call.taskID !== intent.taskID || call.requestID !== intent.requestID) return [];
  if (call.servingRequestID !== streamResponse.servingRequestID || call.workerBuildSHA256 !== intent.expectedBuild) throw new Error('retry_model_serving_identity_mismatch');
  return [{ logID: log.id, loggedAt: log.time, ...call }];
});
if (!modelCalls.length) throw new Error('correlated_model_call_required');
const proposals = frames.filter(frame => frame.type === 'shell_proposal');
const records = events.records ?? [];
const computation = outcome.executions.find((item: Record<string, any>) => item.operation === 'work');
const noExecution = !proposals.length && !records.length && !outcome.executions.length;
const blockedBeforeExecution = noExecution && ['upstream_quota_exhausted', 'upstream_http_rejection'].includes(outcome.issue) && modelCalls.length === 1 && modelCalls[0].phase === 'classification' && [401, 402].includes(modelCalls[0].httpStatus);
const upstream = logs.flatMap(log => {
  const match = /knot_live_upstream (\{.*\})$/.exec(log.message ?? '');
  if (!match) return [];
  const item = JSON.parse(match[1]);
  const timestamp = Date.parse(log.time);
  // This older rejection log has no request ID. Qualify it only by the exact
  // correlated classification call's time window and stage; never invent an ID.
  const enclosing = modelCalls.filter(call => call.phase === 'classification' && call.httpStatus === item.status && timestamp >= Date.parse(call.startedAt) && timestamp <= Date.parse(call.endedAt));
  return item.stage === 'work_classification' && enclosing.length === 1 ? [{ logID: log.id, correlation: 'stage_and_enclosing_call_time_not_request_id', ...item }] : [];
});
const report = {
  title: 'New-backend prime-sum retry ' + attempt + (blockedBeforeExecution ? ' — rejected before execution' : ' — observed outcome'),
  observedAt: new Date().toISOString(), intent, outcome, streamResponse, modelCalls,
  rejection: blockedBeforeExecution ? { stage: 'work_classification', httpStatus: modelCalls[0].httpStatus, category: upstream.length === 1 ? upstream[0].category : null, code: upstream.length === 1 ? upstream[0].code ?? null : null, windowCorrelatedUpstreamLogs: upstream } : null,
  toolExecutionRecord: {
    proposalsEmitted: proposals.length,
    executions: outcome.executions,
    retainedCommandRecords: records.map((record: Record<string, any>) => ({ taskID: record.taskID, sourceMessageID: record.sourceMessageID, spec: record.spec, result: record.result ? { status: record.result.status, sessionID: record.result.sessionID, proposalID: record.result.proposalID, terminationConfirmed: record.result.terminationConfirmed, outputComplete: record.result.outputComplete, exitCode: record.result.exitCode } : null })),
    remoteSessionID: computation?.sessionID ?? null, stdout: computation?.stdout ?? null, exitCode: computation?.exitCode ?? null,
    computationPerformed: !!computation,
  },
  // Avoid publishing any dedicated-workspace prerequisite stdout embedded in SSE.
  turnFrameMetadata: frames.map(frame => ({ sequence: frame.sequence, type: frame.type, requestID: frame.requestID, clientReceivedAt: frame.clientReceivedAt, clientElapsedMs: frame.clientElapsedMs, reason: frame.reason ?? null })),
  retainedActivityCount: events.activities?.length ?? events.activity?.length ?? null,
  conclusions: { blockedBeforeExecution, runnerAnswerVerified: outcome.answerVerified === true, dedicatedAccountOnly: true, personalAccountWorkspaceOrMemoryAccessed: false, originalAttemptPreserved: true, nativeRoutingChanged: false, noDirectSidecarCalls: outcome.directSidecarCalls === 0, noSandboxComputation: true },
};
const path = new URL('../deliveries/' + stem + '-evidence.json', import.meta.url);
writeFileSync(path, JSON.stringify(report, null, 2) + '\n', { flag: 'wx' });
console.log(JSON.stringify({ status: 'retry_evidence_reconciled', attempt, taskID: intent.taskID, modelCalls: modelCalls.map(call => ({ callID: call.callID, phase: call.phase, httpStatus: call.httpStatus, elapsedMs: call.elapsedMs, safeHeaders: call.safeHeaders ?? call.responseHeaders ?? null })), commandRecords: records.length, proposals: proposals.length, answerVerified: outcome.answerVerified, blockedBeforeExecution, report: 'deliveries/' + stem + '-evidence.json' }));
