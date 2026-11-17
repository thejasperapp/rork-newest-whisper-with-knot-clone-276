// Two explicitly authorized once-only fresh scopes. Never loads historical identities.
// --prepare prime|md creates a fresh synthetic user without sending email.
// --run prime|md submits exactly one intent. No replay/retry mode exists.
import { mkdirSync, existsSync, readFileSync, writeFileSync, appendFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { randomUUID, randomBytes, createHash } from 'node:crypto';
import { AcceptanceSkillProvenance, assertAcceptanceIdentity } from './knot-acceptance-provenance';
type Data = Record<string, any>;
const backend = 'https://newest-whisper-with-knot-clone-t6ui3ur-backend.rork.app';
const projectRef = 'uryyyegnbtlmyhqlgndy', supabase = `https://${projectRef}.supabase.co`;
const expectedBuild = 'b738112fad6fc1585433fee3c84f0345fb4b6769f5ab6fe26a594f05533303a9';
const mode = process.argv[2], kind = process.argv[3];
const fact: (value: unknown, reason: string) => asserts value = (value, reason) => { if (!value) throw new Error(reason); };
fact(['--prepare', '--run'].includes(mode) && ['prime', 'md'].includes(kind), 'explicit_fresh_scope_required');
const stem = `fresh-dual-20261115-${kind}`;
const location = join(tmpdir(), 'knot-fresh-dual-mayokn2749ag072e3uvbh-20261115', kind);
const publicPath = (name: string) => new URL(`../deliveries/${stem}-${name}`, import.meta.url).pathname;
const privatePath = (name: string) => join(location, name);
const accountPath = privatePath('fresh-session.json');
const save = (path: string, value: unknown, once = false) => writeFileSync(path, JSON.stringify(value, null, 2) + '\n', { mode: 0o600, flag: once ? 'wx' : 'w' });
const hash = (bytes: string | Uint8Array) => createHash('sha256').update(bytes).digest('hex');
const emit = (data: unknown) => console.log(JSON.stringify(data));
const safe = (e: unknown) => e instanceof Error && /^[a-z0-9_]{1,140}$/.test(e.message) ? e.message : 'transport_or_evidence_unconfirmed';
async function auth(path: string, key: string, body?: unknown, bearer = key): Promise<Data> {
  const r = await fetch(supabase + path, { method: body === undefined ? 'GET' : 'POST', redirect: 'error', headers: { apikey: key, Authorization: 'Bearer ' + bearer, 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(25000) });
  fact(r.ok, 'synthetic_auth_http_' + r.status); return await r.json() as Data;
}
async function prepare() {
  fact(!existsSync(location) && !existsSync(publicPath('account-intent.json')), 'fresh_identity_scope_consumed_no_replay');
  const key = process.env.KNOT_ACCEPTANCE_SUPABASE_SERVICE_ROLE_KEY; fact(key, 'synthetic_admin_key_unavailable');
  mkdirSync(location, { recursive: true, mode: 0o700 });
  save(publicPath('account-intent.json'), { kind, backend, projectRef, startedAt: new Date().toISOString(), syntheticOnly: true, noEmail: true, noReplay: true }, true);
  const email = `knot-dual-qa-${randomUUID()}@example.com`, password = randomBytes(32).toString('base64url');
  const user = await auth('/auth/v1/admin/users', key, { email, password, email_confirm: true, user_metadata: { dedicated_knot_acceptance: true, fresh_dual_20261115: kind, full_name: 'Knot Isolated QA' } });
  fact(user.id && user.email === email && user.user_metadata?.fresh_dual_20261115 === kind, 'fresh_created_identity_mismatch');
  const session = await auth('/auth/v1/token?grant_type=password', key, { email, password });
  fact(session.user?.id === user.id && session.access_token, 'fresh_session_identity_mismatch');
  const confirmed = await auth('/auth/v1/user', key, undefined, session.access_token);
  fact(confirmed.id === user.id && confirmed.user_metadata?.fresh_dual_20261115 === kind, 'fresh_authority_mismatch');
  save(accountPath, { accountID: user.id, workspaceID: 'whisper-' + user.id, projectRef, accessToken: session.access_token }, true);
  emit({ status: 'new_synthetic_identity_verified', kind, accountID: user.id, workspaceID: 'whisper-' + user.id, noEmailSent: true, credentialsPrinted: false });
}
async function run() {
  fact(!existsSync(publicPath('intent.json')), 'fresh_turn_consumed_no_replay');
  const account: Data = JSON.parse(readFileSync(accountPath, 'utf8'));
  const claims = JSON.parse(Buffer.from(account.accessToken.split('.')[1], 'base64url').toString());
  fact(account.projectRef === projectRef && account.workspaceID === 'whisper-' + account.accountID && claims.sub === account.accountID && claims.iss === supabase + '/auth/v1' && claims.exp * 1000 > Date.now() + 1000000, 'fresh_dedicated_session_required');
  const request = async (path: string, body?: unknown, maximumMs = 25000, signal?: AbortSignal) => {
    const r = await fetch(backend + path, { method: body === undefined ? 'GET' : 'POST', redirect: 'error', headers: { 'X-Whisper-Authorization': 'Bearer ' + account.accessToken, 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.any([AbortSignal.timeout(maximumMs), ...(signal ? [signal] : [])]) });
    fact(r.headers.get('X-Knot-Worker-Build') === expectedBuild && (!r.headers.get('X-Knot-Actor-Build') || r.headers.get('X-Knot-Actor-Build') === expectedBuild), 'serving_build_mismatch_no_replay'); return r;
  };
  const checked = async (path: string, body?: unknown): Promise<Data> => { const r = await request(path, body); fact(r.ok, 'managed_http_' + r.status); return await r.json() as Data; };
  const capabilities = await checked('/knot/shell/capabilities'); fact(capabilities.ok && capabilities.principal === 'whisper', 'capability_identity_mismatch');
  const started = Date.now(), requestID = randomUUID(), conversationID = randomUUID(), sourceMessageID = randomUUID();
  const identity = { kind, backend, accountID: account.accountID, workspaceID: account.workspaceID, requestID, taskID: requestID, conversationID, sourceMessageID, expectedBuild, startedAt: new Date(started).toISOString() };
  const ask = kind === 'prime'
    ? 'Use the real workspace to compute the sum of all prime numbers below 1000. Show the actual computation tool card and give the numeric answer based on its command result. Do not create files or update memory for this calculation.'
    : 'Create and deliver a new real Markdown (.md) file titled Rainy Day Reading Checklist. Include five concrete reading-nook preparation tasks, a short book-selection checklist and a Friday-through-Sunday reading schedule. Keep it concise and practical. Deliver the actual Markdown file itself, not a PDF or a description. This is new authoring, not retrieval or repair of any earlier file.';
  const intent = { ...identity, ask, syntheticOnly: true, noAutomaticRetry: true, noHistoricalReplay: true, documentConsent: 'knot_ai_consent_v4', modelConsent: 'default_cloud_routed_only' };
  save(publicPath('intent.json'), intent, true); save(privatePath('intent.json'), intent, true); emit({ status: 'fresh_once_intent_consumed', ...identity });
  const aborter = new AbortController(), seen = new Set<string>(), outstanding = new Map<string, Data>();
  const provenance = new AcceptanceSkillProvenance(account as { accountID: string; workspaceID: string });
  let pending = Promise.resolve(), issue: string | undefined, completed = false, workIncomplete = false, reply = '', stopConfirmed = true, sequence = 0, workAttempted = false;
  const executions: Data[] = [], documents: Data[] = [];
  const stop = async () => { aborter.abort(); for (const p of outstanding.values()) { try { const r = await checked('/knot/shell/cancel', { bot: 'main', conversationID, proposalID: p.id }); save(privatePath(p.id + '-cancel.json'), r); if (!r.terminationConfirmed) stopConfirmed = false; } catch { stopConfirmed = false; } } };
  const execute = async (p: Data) => {
    fact(!aborter.signal.aborted && p.bot === 'main' && p.conversationID === conversationID && p.taskID === requestID && p.sourceMessageID === sourceMessageID && /^[a-f0-9-]{36}$/.test(p.id) && !seen.has(p.id) && typeof p.command === 'string', 'owned_proposal_mismatch_no_replay');
    fact(seen.size < 35 && Date.now() - started < 870000 && p.timeoutMs >= 1000 && p.timeoutMs <= 600000, 'owned_acceptance_ceiling');
    if (kind === 'prime') {
      fact(['memory_read', 'communication_read', 'work'].includes(p.operation), 'outside_prime_scope_operation');
      if (p.operation === 'work') {
        fact(!workAttempted, 'one_computation_only_no_replay');
        fact(/1000/.test(p.command) && /sum/.test(p.command) && /print/.test(p.command) && !/\b(?:curl|wget|fetch|requests|subprocess|socket|open|exec|eval|os|pathlib|read_text|write_text)\b|whisper-|\/home\/|\/root\/|\/workspaces\//.test(p.command), 'computation_outside_safe_scope'); workAttempted = true;
      }
    }
    seen.add(p.id); outstanding.set(p.id, p); save(privatePath(p.id + '-proposal.json'), p);
    // Transport and observation encompass the actual admitted proposal budget.
    const response = await request('/knot/shell/execute', { bot: 'main', conversationID, proposalID: p.id, executionVersion: 'knot_shell_automatic_v1', command: p.command, timeoutMs: p.timeoutMs }, p.timeoutMs + 60000);
    fact(response.ok, 'execute_http_' + response.status); let result = await response.json() as Data;
    save(privatePath(p.id + '-execute.json'), result); assertAcceptanceIdentity(p, result, identity);
    let cached = provenance.acceptCache(p, result, identity);
    const until = Math.min(started + 900000, Date.now() + p.timeoutMs + 30000);
    while (!cached && result.sessionID && !(result.terminationConfirmed && result.commandReceipt && result.outputComplete && !result.truncated) && !['cancelled', 'uncertain'].includes(result.status) && Date.now() < until) {
      await new Promise(resolve => setTimeout(resolve, 800)); result = await checked('/knot/shell/status', { bot: 'main', conversationID, proposalID: p.id }); assertAcceptanceIdentity(p, result, identity); cached = provenance.acceptCache(p, result, identity);
    }
    save(privatePath(p.id + '-result.json'), result);
    fact(result.terminationConfirmed && (cached || result.sessionID && result.outputComplete && !result.truncated && result.commandReceipt?.session_id === result.sessionID && result.commandReceipt?.proposal_id === p.id), 'execution_unconfirmed_no_replay');
    if (!cached) { fact(result.providerReceipt?.user_id === account.workspaceID && result.providerReceipt?.session_id === result.sessionID, 'workspace_receipt_mismatch'); provenance.remember(p, result, identity); }
    const summary = { proposalID: p.id, operation: p.operation, documentStage: p.documentInvocation?.stage, status: result.status, exitCode: result.exitCode, sessionID: result.sessionID, commandReceipt: result.commandReceipt, providerReceipt: result.providerReceipt, terminationConfirmed: result.terminationConfirmed, outputComplete: result.outputComplete, truncated: result.truncated, cached, stdoutSHA256: hash(result.stdout ?? ''), ...(kind === 'prime' && p.operation === 'work' ? { command: p.command, stdout: result.stdout, stderr: result.stderr } : {}) };
    executions.push(summary); outstanding.delete(p.id); emit(summary);
  };
  let retained: Data = {};
  try {
    const response = await request('/knot/chat/stream', { requestID, bot: 'main', conversationID, sourceMessageID, sourceCreatedAt: started, consentVersion: 'knot_ai_consent_v4', message: ask, healthContext: '', history: [], isWebQuery: false, sharedConversation: false, timezone: 'UTC', foregroundTurnVersion: 'knot_foreground_turn_v1', workProgressVersion: 'knot_work_progress_v1', ...(kind === 'md' ? { documentProgramVersion: 'knot_document_program_v3' } : {}), taskExperienceVersion: 'knot_task_experience_v1', clarificationVersion: 'knot_clarification_v1' }, 945000, aborter.signal);
    save(privatePath('stream-response.json'), { status: response.status, workerBuild: response.headers.get('X-Knot-Worker-Build'), actorBuild: response.headers.get('X-Knot-Actor-Build'), requestID: response.headers.get('X-Knot-Request-ID') });
    fact(response.ok && response.body, 'stream_http_' + response.status);
    const reader = response.body.getReader(), decoder = new TextDecoder(); let buffer = '';
    try { for (;;) { const part = await reader.read(); if (part.done) break; buffer += decoder.decode(part.value, { stream: true }); let at: number;
      while ((at = buffer.indexOf('\n\n')) >= 0) { const packet = buffer.slice(0, at); buffer = buffer.slice(at + 2); const text = packet.split('\n').filter(line => line.startsWith('data:')).map(line => line.slice(5).trimStart()).join('\n'); if (!text) continue;
        const frame = JSON.parse(text); fact(frame.requestID === requestID && frame.sequence === ++sequence, 'stream_identity_or_sequence_mismatch');
        appendFileSync(privatePath('frames.jsonl'), JSON.stringify({ ...frame, receivedAt: new Date().toISOString(), elapsedMs: Date.now() - started }) + '\n', { mode: 0o600 });
        if (frame.type === 'shell_proposal') pending = pending.then(() => execute(frame.proposal)).catch(async e => { issue ??= safe(e); await stop(); });
        if (frame.type === 'complete') { completed = true; workIncomplete = frame.workIncomplete === true; reply = frame.reply ?? ''; if (workIncomplete) issue ??= frame.reason ?? 'work_incomplete'; }
        if (['error', 'rejected', 'document_work_unavailable'].includes(frame.type)) issue ??= frame.reason ?? frame.error ?? frame.type;
      }
    } fact(!buffer.trim(), 'incomplete_stream_frame'); } finally { reader.releaseLock(); }
  } catch (e) { issue ??= safe(e); await stop(); }
  await pending; if (outstanding.size) await stop();
  try {
    retained = await checked('/knot/shell/events', { bot: 'main', conversationID }); save(privatePath('events.json'), retained);
    for (const row of retained.records ?? []) fact(row.taskID === requestID && row.sourceMessageID === sourceMessageID && row.spec?.conversationID === conversationID, 'retained_identity_mismatch');
    for (const doc of retained.documents ?? []) {
      fact(kind === 'md' && /^[a-f0-9]{64}$/.test(doc.id) && doc.format === 'md' && doc.size > 0 && doc.size < 1000000 && doc.sourceMessageID === sourceMessageID, 'captured_document_identity_mismatch');
      const response = await request('/knot/shell/documents', { bot: 'main', conversationID, documentID: doc.id, action: 'file' }); fact(response.ok, 'download_http_' + response.status);
      const bytes = new Uint8Array(await response.arrayBuffer()), mime = response.headers.get('Content-Type');
      fact(hash(bytes) === doc.sha256 && response.headers.get('X-Knot-SHA256') === doc.sha256 && bytes.length === doc.size, 'captured_byte_mismatch');
      fact(!!mime && /text\/(markdown|plain)/.test(mime), 'markdown_mime_mismatch');
      const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes); fact(/Rainy Day Reading Checklist/i.test(text) && /Friday/i.test(text) && /Saturday/i.test(text) && /Sunday/i.test(text), 'markdown_content_scope_mismatch');
      const path = publicPath('original.md'); fact(!existsSync(path), 'immutable_delivery_collision'); writeFileSync(path, bytes, { flag: 'wx' });
      documents.push({ ...doc, downloadedSHA256: hash(bytes), downloadedSize: bytes.length, mime, contentDisposition: response.headers.get('Content-Disposition'), originalPath: path, exactBytesVerified: true });
    }
  } catch (e) { issue ??= safe(e); }
  const computation = executions.find(e => e.operation === 'work');
  // Expected numeric value never appears in the model prompt or executed command supplied by this harness.
  const answerVerified = kind === 'prime' && computation?.status === 'completed' && computation.exitCode === 0 && computation.stdout?.trim() === '76127' && /\b76,?127\b/.test(reply);
  const passed = !issue && completed && !workIncomplete && stopConfirmed && (kind === 'prime' ? answerVerified : documents.length === 1);
  const result = { ...identity, endedAt: new Date().toISOString(), elapsedMs: Date.now() - started, completed, workIncomplete, issue: issue ?? null, stopConfirmed, passed, answerVerified, reply, executions, documents, retainedRecordCount: retained.records?.length ?? 0, frameCount: sequence, chatSubmissions: 1, directSidecarCalls: 0, personalAccountAccessed: false };
  save(privatePath('outcome.json'), result); save(publicPath('outcome.json'), result, true);
  save(publicPath('evidence.json'), { intent, outcome: result, retained }, true); emit(result); if (!passed) process.exitCode = 2;
}
(mode === '--prepare' ? prepare() : run()).catch(e => { emit({ status: 'blocked_no_automatic_replay', reason: safe(e) }); process.exitCode = 2; });
