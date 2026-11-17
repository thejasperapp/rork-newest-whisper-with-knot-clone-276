// Fresh PDF-only synthetic acceptance. Never imports sessions, tokens or historical provenance.
// --prepare creates one new no-email identity. --run consumes one immutable intent before dispatch.
import { mkdirSync, existsSync, readFileSync, writeFileSync, appendFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { randomUUID, randomBytes, createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { knotSourceBuildSHA256 } from '../functions/knot-source-build';
import { AcceptanceSkillProvenance, assertAcceptanceIdentity } from './knot-acceptance-provenance';
type Data = Record<string, any>;
const backend = 'https://newest-whisper-with-knot-clone-t6ui3ur-backend.rork.app';
const projectRef = 'uryyyegnbtlmyhqlgndy', supabase = `https://${projectRef}.supabase.co`;
const location = join(tmpdir(), 'knot-pdf-fresh-tap-mayokn2749ag072e3uvbh-20261115');
const publicPath = (name: string) => new URL(`../deliveries/pdf-fresh-tap-20261115-${name}`, import.meta.url).pathname;
const privatePath = (name: string) => join(location, name);
const save = (path: string, value: unknown, once = false) => writeFileSync(path, JSON.stringify(value, null, 2) + '\n', { mode: 0o600, flag: once ? 'wx' : 'w' });
const hash = (bytes: string | Uint8Array) => createHash('sha256').update(bytes).digest('hex');
const fact: (v: unknown, reason: string) => asserts v = (v, reason) => { if (!v) throw new Error(reason); };
const emit = (v: unknown) => console.log(JSON.stringify(v));
const safe = (e: unknown) => e instanceof Error && /^[a-z0-9_]{1,140}$/.test(e.message) ? e.message : 'transport_or_evidence_unconfirmed';
async function auth(path: string, key: string, body?: unknown, bearer = key): Promise<Data> {
  const r = await fetch(supabase + path, { method: body === undefined ? 'GET' : 'POST', redirect: 'error', headers: { apikey: key, Authorization: 'Bearer ' + bearer, 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(25000) });
  fact(r.ok, 'synthetic_auth_http_' + r.status); return await r.json() as Data;
}
async function prepare() {
  fact(!existsSync(location) && !existsSync(publicPath('account-intent.json')), 'fresh_identity_scope_consumed_no_replay');
  const key = process.env.KNOT_ACCEPTANCE_SUPABASE_SERVICE_ROLE_KEY; fact(key, 'synthetic_admin_key_unavailable');
  mkdirSync(location, { recursive: true, mode: 0o700 });
  save(publicPath('account-intent.json'), { backend, projectRef, expectedBuild: knotSourceBuildSHA256, startedAt: new Date().toISOString(), syntheticOnly: true, noEmail: true, noReplay: true }, true);
  const email = `knot-pdf-qa-${randomUUID()}@example.com`, password = randomBytes(32).toString('base64url');
  const user = await auth('/auth/v1/admin/users', key, { email, password, email_confirm: true, user_metadata: { dedicated_knot_acceptance: true, fresh_pdf_tap_20261115: true, full_name: 'Knot PDF Isolated QA' } });
  fact(user.id && user.email === email && user.user_metadata?.fresh_pdf_tap_20261115 === true, 'fresh_created_identity_mismatch');
  const session = await auth('/auth/v1/token?grant_type=password', key, { email, password });
  fact(session.user?.id === user.id && session.access_token, 'fresh_session_identity_mismatch');
  const confirmed = await auth('/auth/v1/user', key, undefined, session.access_token);
  fact(confirmed.id === user.id && confirmed.user_metadata?.fresh_pdf_tap_20261115 === true, 'fresh_authority_mismatch');
  save(privatePath('fresh-session.json'), { accountID: user.id, workspaceID: 'whisper-' + user.id, projectRef, accessToken: session.access_token, expectedBuild: knotSourceBuildSHA256 }, true);
  emit({ status: 'new_synthetic_identity_verified', accountID: user.id, workspaceID: 'whisper-' + user.id, noEmailSent: true, credentialsPrinted: false });
}
async function run() {
  fact(!existsSync(publicPath('intent.json')), 'fresh_turn_consumed_no_replay');
  const account: Data = JSON.parse(readFileSync(privatePath('fresh-session.json'), 'utf8'));
  const claims = JSON.parse(Buffer.from(account.accessToken.split('.')[1], 'base64url').toString());
  fact(account.projectRef === projectRef && account.expectedBuild === knotSourceBuildSHA256 && account.workspaceID === 'whisper-' + account.accountID && claims.sub === account.accountID && claims.iss === supabase + '/auth/v1' && claims.exp * 1000 > Date.now() + 1000000, 'fresh_dedicated_session_required');
  const request = async (path: string, body?: unknown, maximumMs = 25000, signal?: AbortSignal) => {
    const r = await fetch(backend + path, { method: body === undefined ? 'GET' : 'POST', redirect: 'error', headers: { 'X-Whisper-Authorization': 'Bearer ' + account.accessToken, 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.any([AbortSignal.timeout(maximumMs), ...(signal ? [signal] : [])]) });
    fact(r.headers.get('X-Knot-Worker-Build') === account.expectedBuild && (!r.headers.get('X-Knot-Actor-Build') || r.headers.get('X-Knot-Actor-Build') === account.expectedBuild), 'serving_build_mismatch_no_replay'); return r;
  };
  const checked = async (path: string, body?: unknown): Promise<Data> => { const r = await request(path, body); fact(r.ok, 'managed_http_' + r.status); return await r.json() as Data; };
  const capabilities = await checked('/knot/shell/capabilities'); fact(capabilities.ok && capabilities.principal === 'whisper', 'capability_identity_mismatch');
  const started = Date.now(), requestID = randomUUID(), conversationID = randomUUID(), sourceMessageID = randomUUID();
  const identity = { backend, accountID: account.accountID, workspaceID: account.workspaceID, requestID, taskID: requestID, conversationID, sourceMessageID, expectedBuild: account.expectedBuild, startedAt: new Date(started).toISOString() };
  const ask = 'Create and deliver a new real two-page PDF titled Rainy Day Reading Plan. Page one: five practical reading-nook preparation tasks and a short book-selection checklist. Page two: a Friday, Saturday and Sunday reading schedule. Use considered typography, warm cream and dark ink, clear hierarchy and comfortable margins. Keep all text concise and readable. This is new authoring, not retrieval or repair of any earlier file. Deliver the actual PDF, not Markdown or an explanation about PDFs.';
  const intent = { ...identity, ask, syntheticOnly: true, noAutomaticRetry: true, noHistoricalReplay: true, documentConsent: 'knot_ai_consent_v4', modelConsent: 'default_cloud_routed_only' };
  save(publicPath('intent.json'), intent, true); save(privatePath('intent.json'), intent, true); emit({ status: 'fresh_once_intent_consumed', ...identity });
  const aborter = new AbortController(), seen = new Set<string>(), outstanding = new Map<string, Data>();
  const provenance = new AcceptanceSkillProvenance(account as { accountID: string; workspaceID: string });
  let pending = Promise.resolve(), issue: string | undefined, completed = false, workIncomplete = false, reply = '', stopConfirmed = true, sequence = 0;
  const executions: Data[] = [], documents: Data[] = [];
  const stop = async () => { aborter.abort(); for (const p of outstanding.values()) { try { const r = await checked('/knot/shell/cancel', { bot: 'main', conversationID, proposalID: p.id }); save(privatePath(p.id + '-cancel.json'), r); if (!r.terminationConfirmed) stopConfirmed = false; } catch { stopConfirmed = false; } } };
  const execute = async (p: Data) => {
    fact(!aborter.signal.aborted && p.bot === 'main' && p.conversationID === conversationID && p.taskID === requestID && p.sourceMessageID === sourceMessageID && /^[a-f0-9-]{36}$/.test(p.id) && !seen.has(p.id) && typeof p.command === 'string', 'owned_proposal_mismatch_no_replay');
    fact(seen.size < 35 && Date.now() - started < 870000 && p.timeoutMs >= 1000 && p.timeoutMs <= 600000, 'owned_acceptance_ceiling');
    seen.add(p.id); outstanding.set(p.id, p); save(privatePath(p.id + '-proposal.json'), p);
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
    const summary = { proposalID: p.id, operation: p.operation, documentStage: p.documentInvocation?.stage, status: result.status, exitCode: result.exitCode, sessionID: result.sessionID, commandReceipt: result.commandReceipt, providerReceipt: result.providerReceipt, terminationConfirmed: result.terminationConfirmed, outputComplete: result.outputComplete, truncated: result.truncated, cached, stdoutSHA256: hash(result.stdout ?? '') };
    executions.push(summary); outstanding.delete(p.id); emit(summary);
  };
  let retained: Data = {};
  try {
    const response = await request('/knot/chat/stream', { requestID, bot: 'main', conversationID, sourceMessageID, sourceCreatedAt: started, consentVersion: 'knot_ai_consent_v4', message: ask, healthContext: '', history: [], isWebQuery: false, sharedConversation: false, timezone: 'UTC', foregroundTurnVersion: 'knot_foreground_turn_v1', workProgressVersion: 'knot_work_progress_v1', documentProgramVersion: 'knot_document_program_v3', taskExperienceVersion: 'knot_task_experience_v1', clarificationVersion: 'knot_clarification_v1' }, 945000, aborter.signal);
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
      fact(/^[a-f0-9]{64}$/.test(doc.id) && doc.format === 'pdf' && doc.size > 0 && doc.size < 20000000 && doc.sourceMessageID === sourceMessageID && doc.pages === 2, 'captured_document_identity_mismatch');
      const response = await request('/knot/shell/documents', { bot: 'main', conversationID, documentID: doc.id, action: 'file' }); fact(response.ok, 'download_http_' + response.status);
      const bytes = new Uint8Array(await response.arrayBuffer()), mime = response.headers.get('Content-Type');
      fact(hash(bytes) === doc.sha256 && response.headers.get('X-Knot-SHA256') === doc.sha256 && bytes.length === doc.size && mime?.includes('application/pdf') && new TextDecoder().decode(bytes.slice(0, 5)) === '%PDF-', 'captured_pdf_byte_mismatch');
      const path = publicPath('original.pdf'); fact(!existsSync(path), 'immutable_delivery_collision'); writeFileSync(path, bytes, { flag: 'wx' });
      const info = spawnSync('pdfinfo', [path], { encoding: 'utf8' }), extracted = spawnSync('pdftotext', [path, '-'], { encoding: 'utf8' });
      fact(info.status === 0 && /^Pages:\s+2$/m.test(info.stdout) && extracted.status === 0 && /Rainy Day Reading Plan/i.test(extracted.stdout) && ['Friday', 'Saturday', 'Sunday'].every(day => extracted.stdout.includes(day)), 'independent_pdf_content_unconfirmed');
      const render = spawnSync('pdftoppm', ['-png', '-scale-to', '1200', path, privatePath('render')], { encoding: 'utf8' }); fact(render.status === 0, 'independent_pdf_render_unconfirmed');
      documents.push({ ...doc, downloadedSHA256: hash(bytes), downloadedSize: bytes.length, mime, originalPath: path, exactBytesVerified: true, independentPageCount: 2, independentTextChecked: true, localRenderCompleted: true, visualInspection: 'pending_human_or_agent_image_read' });
    }
  } catch (e) { issue ??= safe(e); }
  const passed = !issue && completed && !workIncomplete && stopConfirmed && documents.length === 1;
  const result = { ...identity, endedAt: new Date().toISOString(), elapsedMs: Date.now() - started, completed, workIncomplete, issue: issue ?? null, stopConfirmed, passed, reply, executions, documents, retainedRecordCount: retained.records?.length ?? 0, frameCount: sequence, chatSubmissions: 1, directSidecarCalls: 0, personalAccountAccessed: false, quarantinedNoReplay: !passed };
  save(privatePath('outcome.json'), result); save(publicPath('outcome.json'), result, true); save(publicPath('evidence.json'), { intent, outcome: result, retained }, true); emit(result); if (!passed) process.exitCode = 2;
}
const mode = process.argv[2];
fact(['--prepare', '--run'].includes(mode), 'explicit_fresh_pdf_mode_required');
(mode === '--prepare' ? prepare() : run()).catch(e => { emit({ status: 'blocked_no_automatic_replay', reason: safe(e) }); process.exitCode = 2; });
