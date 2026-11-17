// Explicitly authorized November 14 acceptance. Fixed account, backend and once
// scope. Never reads account.json, sends email, resets a password or creates a user.
// --prepare-session issues an admin test session ONLY for the exact existing user.
// --run --expected-build <sha256> submits ONE fresh turn; never retry this mode.
// --collect is read-only recovery of evidence from that exact turn, not a replay.
// --authorized-retry --attempt 01..03 is separately owner-approved November 14
// fresh-turn retry scope. Original once intent/outcome remain immutable.
import { mkdirSync, existsSync, readFileSync, writeFileSync, appendFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash, randomUUID } from 'node:crypto';
import { assertAcceptanceIdentity } from './knot-acceptance-provenance';

const backend = 'https://newest-whisper-with-knot-clone-t6ui3ur-backend.rork.app';
const projectRef = 'uryyyegnbtlmyhqlgndy';
const accountID = 'e00a9064-5f85-40bb-9f44-8bd60f90d24a';
const workspaceID = 'whisper-' + accountID;
const supabase = 'https://' + projectRef + '.supabase.co';
const baseDirectory = join(tmpdir(), 'knot-managed-prime-mayokn2749ag072e3uvbh-20261114');
const retryMode = process.argv.includes('--authorized-retry');
const attempt = process.argv.includes('--attempt') ? process.argv[process.argv.indexOf('--attempt') + 1] : '';
if ((retryMode && !/^0[1-3]$/.test(attempt ?? '')) || (!retryMode && attempt)) throw new Error('explicit_bounded_retry_attempt_required');
const stem = retryMode ? 'managed-prime-retry-20261114-' + attempt : 'managed-prime-once-20261114';
const directory = retryMode ? join(baseDirectory, 'retry-' + attempt) : baseDirectory;
const sessionPath = join(baseDirectory, 'dedicated-session.json');
const scope = new URL('../deliveries/' + stem + '-intent.json', import.meta.url);
const outcomePath = new URL('../deliveries/' + stem + '-outcome.json', import.meta.url);
const expectedBuild = process.argv[process.argv.indexOf('--expected-build') + 1];
const fact: (value: unknown, code: string) => asserts value = (value, code) => { if (!value) throw new Error(code); };
const digest = (value: string) => createHash('sha256').update(value).digest('hex');
const save = (name: string, value: unknown) => writeFileSync(join(directory, name), JSON.stringify(value, null, 2) + '\n', { mode: 0o600 });
const emit = (value: unknown) => console.log(JSON.stringify(value));
const safeReason = (error: unknown) => error instanceof Error && /^[a-z0-9_]{1,120}$/.test(error.message) ? error.message : 'transport_or_evidence_unconfirmed';
type Data = Record<string, any>;
mkdirSync(directory, { recursive: true, mode: 0o700 });

async function authJSON(path: string, key: string, body?: unknown, bearer = key): Promise<Data> {
  const response = await fetch(supabase + path, { redirect: 'error', method: body === undefined ? 'GET' : 'POST', headers: { apikey: key, Authorization: 'Bearer ' + bearer, 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(20000) });
  fact(response.ok, 'dedicated_auth_http_' + response.status);
  return await response.json() as Data;
}
async function prepareSession() {
  fact(!existsSync(sessionPath) && !existsSync(join(directory, 'session-issuance-intent.json')), 'dedicated_session_issuance_already_attempted');
  fact(!existsSync(scope), 'prime_scope_already_consumed');
  const key = process.env.KNOT_ACCEPTANCE_SUPABASE_SERVICE_ROLE_KEY;
  fact(key, 'dedicated_admin_credential_unavailable');
  // Credential is opaque. Actual exact-user validation, not a JWT format guess.
  const user = await authJSON('/auth/v1/admin/users/' + accountID, key);
  fact(user.id === accountID && user.user_metadata?.dedicated_knot_acceptance === true && typeof user.email === 'string' && /^knot-acceptance-[a-f0-9-]+@example\.com$/.test(user.email), 'exact_existing_dedicated_user_required');
  writeFileSync(join(directory, 'session-issuance-intent.json'), JSON.stringify({ accountID, workspaceID, projectRef, startedAt: new Date().toISOString(), method: 'admin_magiclink_verify_no_send', authorizedScope: 'dedicated_acceptance_only', noPersonalAccountAccess: true }), { flag: 'wx', mode: 0o600 });
  const generated = await authJSON('/auth/v1/admin/generate_link', key, { type: 'magiclink', email: user.email });
  fact(generated.id === accountID && typeof generated.hashed_token === 'string' && generated.hashed_token, 'generated_link_dedicated_identity_mismatch');
  const session = await authJSON('/auth/v1/verify', key, { type: 'email', token_hash: generated.hashed_token });
  fact(session.user?.id === accountID && typeof session.access_token === 'string', 'issued_session_dedicated_identity_mismatch');
  const claims = JSON.parse(Buffer.from(session.access_token.split('.')[1], 'base64url').toString());
  fact(claims.sub === accountID && claims.exp * 1000 > Date.now() + 300000 && claims.iss === supabase + '/auth/v1', 'issued_session_claims_mismatch');
  const confirmed = await authJSON('/auth/v1/user', key, undefined, session.access_token);
  fact(confirmed.id === accountID && confirmed.user_metadata?.dedicated_knot_acceptance === true, 'issued_session_authority_mismatch');
  save('dedicated-session.json', { accountID, workspaceID, projectRef, accessToken: session.access_token, issuedAt: new Date().toISOString() });
  emit({ status: 'admin_issued_dedicated_test_session_verified', accountID, workspaceID, noAccountCreation: true, noPasswordChange: true, noEmailSent: true, personalAccountAccessed: false });
}
function loadSession(): Data {
  const saved = JSON.parse(readFileSync(sessionPath, 'utf8'));
  const claims = JSON.parse(Buffer.from(saved.accessToken.split('.')[1], 'base64url').toString());
  fact(saved.accountID === accountID && saved.workspaceID === workspaceID && saved.projectRef === projectRef && claims.sub === accountID && claims.exp * 1000 > Date.now() + 60000 && claims.iss === supabase + '/auth/v1', 'dedicated_session_required');
  return saved;
}
async function managed(path: string, token: string, body?: unknown, maximumMs = 25000, signal?: AbortSignal): Promise<Response> {
  const response = await fetch(backend + path, { redirect: 'error', method: body === undefined ? 'GET' : 'POST', headers: { 'X-Whisper-Authorization': 'Bearer ' + token, 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.any([AbortSignal.timeout(maximumMs), ...(signal ? [signal] : [])]) });
  if (process.argv.includes('--run') || (retryMode && !process.argv.includes('--collect'))) {
    fact(response.headers.get('X-Knot-Worker-Build') === expectedBuild, 'serving_worker_build_mismatch_no_replay');
    const actor = response.headers.get('X-Knot-Actor-Build');
    fact(!actor || actor === expectedBuild, 'serving_actor_build_mismatch_no_replay');
  }
  return response;
}
async function checked(path: string, token: string, body?: unknown): Promise<Data> {
  const response = await managed(path, token, body);
  if (!response.ok) { await response.body?.cancel(); throw new Error('managed_http_' + response.status); }
  return await response.json() as Data;
}
async function collect(token: string, identity: Data) {
  fact(identity.accountID === accountID && identity.workspaceID === workspaceID && identity.backend === backend, 'collection_identity_mismatch');
  const events = await checked('/knot/shell/events', token, { bot: 'main', conversationID: identity.conversationID });
  save('events.json', events);
  const summaries: Data[] = [];
  for (const record of events.records ?? []) {
    fact(record.taskID === identity.requestID && record.sourceMessageID === identity.sourceMessageID && record.spec?.conversationID === identity.conversationID, 'retained_record_identity_mismatch');
    const proposalID = record.spec.id;
    const detail = await checked('/knot/shell/events', token, { bot: 'main', conversationID: identity.conversationID, proposalID });
    save(proposalID + '-events.json', detail);
    if (record.result?.sessionID) save(proposalID + '-log.json', await checked('/knot/shell/log', token, { bot: 'main', conversationID: identity.conversationID, proposalID }));
    summaries.push({ proposalID, operation: record.spec.operation, taskID: record.taskID, status: record.result?.status, sessionID: record.result?.sessionID });
  }
  return { records: summaries, activityCount: events.activities?.length ?? events.activity?.length ?? null };
}
function assertRetryAuthorization() {
  if (!retryMode) return;
  const authorization = JSON.parse(readFileSync(new URL('../deliveries/managed-prime-retry-20261114-authorization.json', import.meta.url), 'utf8'));
  fact(authorization.accountID === accountID && authorization.workspaceID === workspaceID && authorization.backend === backend && authorization.ownerApprovedFreshRetries === true && authorization.maximumAttemptsThisBatch === 3, 'fresh_retry_authorization_required');
  const previousStem = attempt === '01' ? 'managed-prime-once-20261114' : 'managed-prime-retry-20261114-0' + (Number(attempt) - 1);
  const previous = JSON.parse(readFileSync(new URL('../deliveries/' + previousStem + '-outcome.json', import.meta.url), 'utf8'));
  const evidence = JSON.parse(readFileSync(new URL('../deliveries/' + previousStem + '-evidence.json', import.meta.url), 'utf8'));
  fact(previous.accountID === accountID && previous.workspaceID === workspaceID && previous.backend === backend && previous.stopConfirmed === true && previous.completed === false && ['upstream_quota_exhausted', 'upstream_http_rejection'].includes(previous.issue) && previous.executions?.length === 0 && previous.retained?.records?.length === 0, 'previous_turn_progress_or_uncertainty_no_retry');
  fact(evidence.intent?.requestID === previous.requestID && evidence.outcome?.requestID === previous.requestID && evidence.toolExecutionRecord?.proposalsEmitted === 0 && evidence.toolExecutionRecord?.retainedCommandRecords?.length === 0 && evidence.toolExecutionRecord?.computationPerformed === false && evidence.modelCalls?.length === 1 && evidence.modelCalls[0].phase === 'classification' && [401, 402].includes(evidence.modelCalls[0].httpStatus), 'exact_preexecution_rejection_evidence_required');
}
async function run() {
  assertRetryAuthorization();
  fact(process.argv.includes('--expected-build') && /^[a-f0-9]{64}$/.test(expectedBuild ?? ''), 'explicit_serving_build_required');
  fact(!existsSync(scope) && !existsSync(join(directory, 'intent.json')), 'prime_scope_already_consumed_no_replay');
  const session = loadSession(), token = session.accessToken;
  const capabilities = await checked('/knot/shell/capabilities', token);
  fact(capabilities.ok === true && capabilities.service === 'knot-sidecar' && capabilities.principal === 'whisper', 'new_backend_capability_verification_failed');
  const requestID = randomUUID(), conversationID = randomUUID(), sourceMessageID = randomUUID();
  const started = Date.now();
  const identity = { backend, accountID, workspaceID, requestID, taskID: requestID, conversationID, sourceMessageID, expectedBuild, startedAt: new Date(started).toISOString() };
  const ask = 'Use the real workspace to compute the sum of all prime numbers below 1000. Show the actual computation tool card and give the numeric answer based on its command result. Do not create files or update memory for this calculation.';
  const intent = { title: retryMode ? 'Owner-authorized fresh prime-sum retry ' + attempt : 'One authorized new-backend prime-sum turn', ...identity, ask, ...(retryMode ? { retryAuthorization: 'managed-prime-retry-20261114-authorization', attempt } : {}), noAutomaticRetry: true, noHistoricalReplay: true, dedicatedAccountOnly: true, personalAccountAccessed: false };
  writeFileSync(scope, JSON.stringify(intent, null, 2) + '\n', { flag: 'wx' });
  save('intent.json', intent); emit({ status: 'one_turn_scope_consumed', ...identity });
  const aborter = new AbortController();
  const seen = new Set<string>(), outstanding = new Map<string, Data>();
  const executions: Data[] = [], frames: Data[] = [];
  let workAttempted = false, pending = Promise.resolve(), issue: string | undefined;
  let reply = '', completed = false, workIncomplete = false, completionReceivedMs: number | null = null, stopConfirmed = true;
  const stop = async () => {
    aborter.abort();
    for (const proposal of outstanding.values()) {
      try { const value = await checked('/knot/shell/cancel', token, { bot: 'main', conversationID, proposalID: proposal.id }); save(proposal.id + '-cancel.json', value); if (!value.terminationConfirmed) stopConfirmed = false; }
      catch { stopConfirmed = false; }
    }
  };
  const execute = async (proposal: Data) => {
    fact(!aborter.signal.aborted, 'turn_already_stopped');
    fact(proposal.bot === 'main' && proposal.conversationID === conversationID && proposal.taskID === requestID && proposal.sourceMessageID === sourceMessageID && /^[a-f0-9-]{36}$/.test(proposal.id) && !seen.has(proposal.id) && typeof proposal.command === 'string', 'owned_proposal_mismatch_or_replay');
    fact(['memory_read', 'communication_read', 'work'].includes(proposal.operation), 'outside_prime_scope_operation');
    // No arbitrary account paths/network/file reads in the computational command.
    if (proposal.operation === 'work') {
      fact(!workAttempted, 'one_computation_only_no_replay');
      fact(/1000/.test(proposal.command) && /sum/.test(proposal.command) && /print/.test(proposal.command) && !/\b(?:curl|wget|fetch|requests|subprocess|socket|open|exec|eval|os|pathlib|read_text|write_text)\b|whisper-|\/home\/|\/root\/|\/workspaces\//.test(proposal.command), 'computation_command_outside_safe_scope');
      workAttempted = true;
    }
    seen.add(proposal.id); outstanding.set(proposal.id, proposal); save(proposal.id + '-proposal.json', proposal);
    const response = await managed('/knot/shell/execute', token, { bot: 'main', conversationID, proposalID: proposal.id, executionVersion: 'knot_shell_automatic_v1', command: proposal.command, timeoutMs: proposal.timeoutMs }, 160000);
    const result = await response.json() as Data; save(proposal.id + '-execute.json', result);
    fact(response.ok, 'execution_http_' + response.status);
    assertAcceptanceIdentity(proposal, result, { conversationID, requestID, sourceMessageID });
    let final = result; const until = Date.now() + 15000;
    while (final.sessionID && !(final.terminationConfirmed && final.commandReceipt && final.outputComplete && !final.truncated) && final.status !== 'cancelled' && Date.now() < until) {
      await new Promise(resolve => setTimeout(resolve, 650));
      final = await checked('/knot/shell/status', token, { bot: 'main', conversationID, proposalID: proposal.id });
      assertAcceptanceIdentity(proposal, final, { conversationID, requestID, sourceMessageID });
    }
    save(proposal.id + '-result.json', final);
    fact(final.providerReceipt?.user_id === workspaceID && final.providerReceipt?.session_id === final.sessionID, 'exact_dedicated_workspace_receipt_required');
    fact(final.terminationConfirmed === true && final.outputComplete === true && final.truncated === false && final.commandReceipt?.session_id === final.sessionID && final.commandReceipt?.proposal_id === proposal.id, 'execution_unconfirmed_no_replay');
    const summary = { proposalID: proposal.id, operation: proposal.operation, command: proposal.command, status: final.status, exitCode: final.exitCode, sessionID: final.sessionID, commandReceipt: final.commandReceipt, providerReceipt: final.providerReceipt, outputComplete: final.outputComplete, terminationConfirmed: final.terminationConfirmed, truncated: final.truncated, stdoutSHA256: digest(final.stdout ?? ''), ...(proposal.operation === 'work' ? { stdout: final.stdout, stderr: final.stderr } : { output: '[dedicated workspace prerequisite output retained privately]' }) };
    executions.push(summary); outstanding.delete(proposal.id); emit({ observation: 'owned_execution_observed', ...summary });
  };
  let servingRequestID: string | null = null;
  try {
    const response = await managed('/knot/chat/stream', token, { requestID, bot: 'main', conversationID, sourceMessageID, sourceCreatedAt: started, consentVersion: 'knot_ai_consent_v4', message: ask, healthContext: '', history: [], isWebQuery: false, sharedConversation: false, timezone: 'UTC', foregroundTurnVersion: 'knot_foreground_turn_v1', workProgressVersion: 'knot_work_progress_v1', taskExperienceVersion: 'knot_task_experience_v1', clarificationVersion: 'knot_clarification_v1' }, 360000, aborter.signal);
    servingRequestID = response.headers.get('X-Knot-Request-ID');
    save('stream-response.json', { status: response.status, servingRequestID, workerBuild: response.headers.get('X-Knot-Worker-Build') });
    fact(response.ok && response.body, 'stream_http_' + response.status);
    const reader = response.body.getReader(), decoder = new TextDecoder(); let buffer = '';
    try {
      for (;;) {
        const part = await reader.read(); if (part.done) break;
        buffer += decoder.decode(part.value, { stream: true }); let at: number;
        while ((at = buffer.indexOf('\n\n')) >= 0) {
          const packet = buffer.slice(0, at); buffer = buffer.slice(at + 2);
          const text = packet.split('\n').filter(line => line.startsWith('data:')).map(line => line.slice(5).trimStart()).join('\n');
          if (!text) continue;
          const frame = JSON.parse(text);
          fact(frame.requestID === requestID && frame.sequence === frames.length + 1, 'stream_identity_or_sequence_mismatch');
          const observed = { ...frame, clientReceivedAt: new Date().toISOString(), clientElapsedMs: Date.now() - started };
          frames.push(observed); appendFileSync(join(directory, 'frames.jsonl'), JSON.stringify(observed) + '\n', { mode: 0o600 });
          if (frame.type === 'shell_proposal') pending = pending.then(() => execute(frame.proposal)).catch(async error => { issue ??= safeReason(error); await stop(); });
          if (frame.type === 'complete') { completed = true; workIncomplete = frame.workIncomplete === true; reply = frame.reply ?? ''; completionReceivedMs ??= Date.now() - started; if (workIncomplete) issue ??= frame.reason ?? 'work_incomplete'; }
          if (['error', 'rejected', 'document_work_unavailable'].includes(frame.type)) issue ??= frame.reason ?? frame.error ?? frame.type;
        }
      }
      fact(!buffer.trim(), 'incomplete_sse_frame');
    } finally { reader.releaseLock(); }
  } catch (error) { issue ??= safeReason(error); await stop(); }
  const streamEndedMs = Date.now() - started;
  await pending;
  if (outstanding.size) await stop();
  let retained: unknown;
  try { retained = await collect(token, identity); } catch (error) { issue ??= safeReason(error); }
  const computation = executions.find(item => item.operation === 'work');
  // Expected value is used ONLY after actual execution as an acceptance check.
  const answerVerified = computation?.status === 'completed' && computation.exitCode === 0 && computation.stdout?.trim() === '76127' && /\b76,?127\b/.test(reply);
  const result = { title: 'Observed new-backend prime-sum turn', ...identity, servingRequestID, endedAt: new Date().toISOString(), elapsedMs: Date.now() - started, completionReceivedMs, streamEndedMs, completed, workIncomplete, issue: issue ?? null, reply, answerVerified, stopConfirmed, executions, retained, frameCount: frames.length, chatSubmissions: 1, directSidecarCalls: 0, personalAccountAccessed: false };
  save('result.json', result); writeFileSync(outcomePath, JSON.stringify(result, null, 2) + '\n', { flag: 'wx' }); emit(result);
  if (issue || !answerVerified || !completed || workIncomplete) process.exitCode = 2;
}
async function main() {
  if (process.argv.includes('--prepare-session')) { fact(!retryMode, 'retry_cannot_reissue_session'); return await prepareSession(); }
  if (process.argv.includes('--run') || (retryMode && !process.argv.includes('--collect'))) return await run();
  if (process.argv.includes('--collect')) { const identity = JSON.parse(readFileSync(scope, 'utf8')); emit(await collect(loadSession().accessToken, identity)); return; }
  throw new Error('explicit_prepare_run_or_readonly_collect_required');
}
main().catch(error => { emit({ status: 'blocked_no_automatic_replay', reason: safeReason(error) }); process.exitCode = 2; });
