// Read-only reconciliation of the one consumed acceptance scope. Feed the
// project-scoped `rork logs --source cloudflare --deployment backend --json`
// output on stdin. No tokens/session file, sidecar or model calls are accessed.
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
const directory = join(tmpdir(), 'knot-managed-prime-mayokn2749ag072e3uvbh-20261114');
const read = (name: string) => JSON.parse(readFileSync(join(directory, name), 'utf8'));
const intent = JSON.parse(readFileSync(new URL('../deliveries/managed-prime-once-20261114-intent.json', import.meta.url), 'utf8'));
const outcome = read('result.json'), streamResponse = read('stream-response.json'), events = read('events.json');
const frames = readFileSync(join(directory, 'frames.jsonl'), 'utf8').trim().split('\n').map(line => JSON.parse(line));
if (intent.accountID !== 'e00a9064-5f85-40bb-9f44-8bd60f90d24a' || intent.workspaceID !== 'whisper-' + intent.accountID || outcome.taskID !== intent.taskID || frames.some((frame, index) => frame.requestID !== intent.requestID || frame.sequence !== index + 1)) throw new Error('exact_acceptance_evidence_required');
const input = await Bun.stdin.text();
const logs = input.trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
const modelCalls = logs.flatMap(log => {
  const match = /knot_model_call (\{.*\})$/.exec(log.message ?? '');
  if (!match) return [];
  const call = JSON.parse(match[1]);
  if (call.taskID !== intent.taskID || call.requestID !== intent.requestID) return [];
  if (call.servingRequestID !== streamResponse.servingRequestID || call.workerBuildSHA256 !== intent.expectedBuild) throw new Error('model_call_serving_identity_mismatch');
  return [{ logID: log.id, loggedAt: log.time, ...call }];
});
if (modelCalls.length !== 1 || modelCalls[0].httpStatus !== 402 || outcome.issue !== 'upstream_quota_exhausted' || outcome.executions.length !== 0 || events.records.length !== 0 || frames.some(frame => frame.type === 'shell_proposal')) throw new Error('unexpected_observation_requires_manual_review');
const report = {
  title: 'One new-backend acceptance attempt — blocked before execution',
  observedAt: new Date().toISOString(), intent, outcome, streamResponse,
  modelCalls,
  rejection: { stage: 'work_classification', httpStatus: 402, category: 'quota_exhausted', code: 'INSUFFICIENT_BALANCE', evidenceLogID: logs.find(log => /knot_live_upstream .*INSUFFICIENT_BALANCE/.test(log.message ?? ''))?.id ?? null },
  toolExecutionRecord: { proposalsEmitted: 0, executions: outcome.executions, retainedCommandRecords: events.records, remoteSessionID: null, stdout: null, exitCode: null, computationPerformed: false },
  turnFrames: frames,
  retainedActivities: events.activities ?? events.activity ?? [],
  conclusions: { authenticatedNewBackend: true, dedicatedSessionOnly: true, backendSidecarDiscovery: 'passed', backendToBoxExecutionProven: false, upstreamProvider: 'unavailable; requested model is not evidence of provider execution', noAutomaticRetry: true, personalAccountWorkspaceOrMemoryAccessed: false, recipesRun: false },
  validation: { focusedBackendStrictCompilation: 'passed', fullEntrypoint: '14 inherited errors; baseline comparison only', nativeChanges: false, deviceInteractionTesting: 'not performed' },
};
const path = new URL('../deliveries/managed-prime-once-20261114-evidence.json', import.meta.url);
writeFileSync(path, JSON.stringify(report, null, 2) + '\n', { flag: 'wx' });
console.log(JSON.stringify({ status: 'exact_turn_evidence_reconciled', taskID: intent.taskID, modelCalls: modelCalls.length, httpStatus: modelCalls[0].httpStatus, callElapsedMs: modelCalls[0].elapsedMs, commandRecords: events.records.length, report: 'deliveries/managed-prime-once-20261114-evidence.json' }));
