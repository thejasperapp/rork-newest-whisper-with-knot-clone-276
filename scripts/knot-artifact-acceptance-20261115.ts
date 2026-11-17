// Fresh isolated artifact acceptance. Never loads earlier account/session state.
// --prepare creates ONE dedicated synthetic account, no email sent.
// --run md|pdf|office|game --expected-build SHA submits each new intent ONCE.
// --collect KIND is read-only evidence/download recovery, never a replay.
import { mkdirSync, existsSync, readFileSync, writeFileSync, appendFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { AcceptanceSkillProvenance, assertAcceptanceIdentity } from './knot-acceptance-provenance';
type Data = Record<string, any>;
const backend = 'https://newest-whisper-with-knot-clone-t6ui3ur-backend.rork.app';
const projectRef = 'uryyyegnbtlmyhqlgndy';
const supabase = `https://${projectRef}.supabase.co`;
const freshFilePass = process.argv.includes('--fresh-file-pass');
const directory = join(tmpdir(), 'knot-artifact-acceptance-mayokn2749ag072e3uvbh-20261115' + (freshFilePass ? '-fresh-file-pass' : ''));
const publicDirectory = new URL('../deliveries/', import.meta.url);
const accountPath = join(directory, 'dedicated-session.json');
const flag = (name: string) => process.argv.includes(name) ? process.argv[process.argv.indexOf(name) + 1] : undefined;
const expectedBuild = flag('--expected-build');
const fact: (value: unknown, reason: string) => asserts value = (value, reason) => { if (!value) throw new Error(reason); };
const hash = (bytes: string | Uint8Array) => createHash('sha256').update(bytes).digest('hex');
const save = (path: string, data: unknown, once = false) => writeFileSync(path, JSON.stringify(data, null, 2) + '\n', { mode: 0o600, flag: once ? 'wx' : 'w' });
const emit = (data: unknown) => console.log(JSON.stringify(data));
const safe = (e: unknown) => e instanceof Error && /^[a-z0-9_]{1,140}$/.test(e.message) ? e.message : 'transport_or_evidence_unconfirmed';
const asks = {
  md: 'Create and deliver a real Markdown (.md) file titled Small Garden Checklist. Include five concrete balcony-gardening tasks, a small watering checklist and a seven-day starter schedule. Keep it concise and practical. Deliver the Markdown file itself, not a PDF or a description of a file.',
  pdf: 'Create and deliver a designed two-page PDF titled Balcony Herbs. Cover basil, mint and chives with light, watering, drainage and harvesting advice and a useful weekly checklist. Use a clean botanical editorial layout, legible type and clear hierarchy. Deliver the actual PDF, not just the source.',
  office: 'Create and deliver an actual Excel (.xlsx) workbook titled Balcony Garden Budget with six plausible sample items, quantity, unit price, calculated line totals and a formula-based grand total. Include a small editable budget and formula-based remaining balance. Clearly label currency USD and sample prices. Deliver the working XLSX file, not a PDF.',
  game: 'Build and deliver a self-contained playable HTML game titled Herb Match. Show six shuffled pairs of herb cards, a move counter, visible matched states, a win message when all pairs are found, and a Restart button. Use original simple CSS artwork, no external dependencies. Include stable data-testid attributes card, moves, restart and win for accessible acceptance checks. Deliver the actual HTML file, not a guide or PDF.'
} as const;
const freshAsks = {
  md: 'Create and deliver a real Markdown (.md) file titled Weekend Picnic Checklist. Include five concrete packing tasks, a food-safety checklist and a Friday-through-Sunday preparation schedule. Keep it concise and practical. Deliver the Markdown file itself, not a PDF or description.',
  pdf: 'Create and deliver a designed two-page PDF titled A Simple Park Picnic. Page 1: practical planning, packing and keeping food cold. Page 2: a Friday-through-Sunday preparation checklist, a wet-weather backup and a short leave-no-trace checklist. Use a clean original editorial layout, legible type, generous margins and clear hierarchy. Deliver the actual two-page PDF, not just source. This is a new guide, not retrieval or repair of an earlier artifact.',
  office: 'Create and deliver an actual Excel (.xlsx) workbook titled Sample Picnic Budget with six plausible picnic items, quantity, sample unit price in USD, calculated line totals and a formula-based grand total. Include an editable budget amount and formula-based remaining balance. Clearly label sample prices. Verify formula recalculation and deliver the working XLSX file, not a PDF. This is a new workbook, not retrieval or repair of an earlier artifact.',
  game: 'Build and deliver a self-contained playable HTML game titled Picnic Pairs. Show six shuffled pairs of picnic-item cards with original inline SVG or CSS artwork, a move counter, visible matched states, a win message after all pairs are found and a Restart button that works both during play and after winning. Restart must clear matches, moves, win state, pending callbacks and reshuffle cards using the same setup as first launch. Use no external dependencies. Include stable data-testid attributes card, moves, restart and win. Verify actual play and post-win Restart on the real final HTML before immutable capture. Deliver the HTML file, not a guide or PDF. This is a new game, not retrieval or repair of any earlier artifact.'
} as const;
type Kind = keyof typeof asks;
async function auth(path: string, key: string, body?: unknown, bearer = key): Promise<Data> {
  const response = await fetch(supabase + path, { method: body ? 'POST' : 'GET', redirect: 'error', headers: { apikey: key, Authorization: 'Bearer ' + bearer, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(25000) });
  fact(response.ok, 'dedicated_auth_http_' + response.status); return await response.json() as Data;
}
async function prepare() {
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  fact(!existsSync(accountPath) && !existsSync(join(directory, 'account-intent.json')), 'dedicated_creation_scope_consumed_no_replay');
  const key = process.env.KNOT_ACCEPTANCE_SUPABASE_SERVICE_ROLE_KEY;
  fact(key, 'dedicated_admin_credential_unavailable');
  if (freshFilePass) save(new URL('artifact-20261115-fresh-file-pass-account-intent.json', publicDirectory).pathname, { startedAt: new Date().toISOString(), syntheticOnly: true, noEmail: true, noReplay: true }, true);
  const email = `knot-artifact-qa-${randomUUID()}@example.com`, password = randomBytes(32).toString('base64url');
  save(join(directory, 'account-intent.json'), { backend, projectRef, startedAt: new Date().toISOString(), syntheticOnly: true, noEmail: true }, true);
  const user = await auth('/auth/v1/admin/users', key, { email, password, email_confirm: true, user_metadata: { dedicated_knot_acceptance: true, artifact_acceptance_20261115: true, full_name: 'Knot Artifact QA' } });
  fact(user.id && user.email === email && user.user_metadata?.artifact_acceptance_20261115 === true, 'dedicated_created_identity_mismatch');
  const session = await auth('/auth/v1/token?grant_type=password', key, { email, password });
  fact(session.user?.id === user.id && session.access_token, 'dedicated_session_identity_mismatch');
  const confirmed = await auth('/auth/v1/user', key, undefined, session.access_token);
  fact(confirmed.id === user.id && confirmed.user_metadata?.artifact_acceptance_20261115 === true, 'dedicated_authority_mismatch');
  save(accountPath, { accountID: user.id, workspaceID: 'whisper-' + user.id, projectRef, accessToken: session.access_token }, true);
  emit({ status: 'fresh_synthetic_identity_verified', accountID: user.id, backend, credentialsPrinted: false, personalAccountAccessed: false, emailSent: false });
}
function load(): Data {
  const account = JSON.parse(readFileSync(accountPath, 'utf8'));
  fact(account.projectRef === projectRef && account.workspaceID === 'whisper-' + account.accountID && account.accessToken, 'dedicated_account_required');
  const claims = JSON.parse(Buffer.from(account.accessToken.split('.')[1], 'base64url').toString());
  fact(claims.sub === account.accountID && claims.iss === supabase + '/auth/v1' && claims.exp * 1000 > Date.now() + 60000, 'fresh_dedicated_session_required'); return account;
}
async function request(account: Data, path: string, body?: unknown, maximumMs = 25000, signal?: AbortSignal) {
  const response = await fetch(backend + path, { method: body === undefined ? 'GET' : 'POST', redirect: 'error', headers: { 'X-Whisper-Authorization': 'Bearer ' + account.accessToken, 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.any([AbortSignal.timeout(maximumMs), ...(signal ? [signal] : [])]) });
  if (expectedBuild) fact(response.headers.get('X-Knot-Worker-Build') === expectedBuild && (!response.headers.get('X-Knot-Actor-Build') || response.headers.get('X-Knot-Actor-Build') === expectedBuild), 'serving_build_mismatch_no_replay');
  return response;
}
async function checked(account: Data, path: string, body?: unknown): Promise<Data> {
  const response = await request(account, path, body); fact(response.ok, 'managed_http_' + response.status); return await response.json() as Data;
}
async function collect(account: Data, identity: Data, location: string) {
  fact(identity.accountID === account.accountID && identity.backend === backend && identity.workspaceID === account.workspaceID, 'collection_identity_mismatch');
  const events = await checked(account, '/knot/shell/events', { bot: 'main', conversationID: identity.conversationID }); save(join(location, 'events.json'), events);
  for (const row of events.records ?? []) fact(row.taskID === identity.requestID && row.sourceMessageID === identity.sourceMessageID && row.spec?.conversationID === identity.conversationID, 'retained_record_identity_mismatch');
  const documents: Data[] = [];
  for (const doc of events.documents ?? []) {
    fact(/^[a-f0-9]{64}$/.test(doc.id) && /^[a-z0-9]{1,12}$/.test(doc.format) && doc.size > 0 && doc.size < 25000000 && doc.sourceMessageID === identity.sourceMessageID, 'captured_document_identity_mismatch');
    const response = await request(account, '/knot/shell/documents', { bot: 'main', conversationID: identity.conversationID, documentID: doc.id, action: 'file' });
    fact(response.ok, 'download_http_' + response.status);
    const bytes = new Uint8Array(await response.arrayBuffer());
    fact(hash(bytes) === doc.sha256 && response.headers.get('X-Knot-SHA256') === doc.sha256 && bytes.length === doc.size, 'captured_download_byte_mismatch');
    const originalPath = join(location, doc.id + '.' + doc.format); writeFileSync(originalPath, bytes, { mode: 0o600 });
    const proofs: Data[] = [];
    for (let index = 0; index < (doc.proofPages ?? []).length; index++) {
      const proof = await request(account, '/knot/shell/documents', { bot: 'main', conversationID: identity.conversationID, documentID: doc.id, action: 'preview', pageIndex: index });
      fact(proof.ok, 'proof_download_http_' + proof.status); const data = new Uint8Array(await proof.arrayBuffer());
      fact(data.length > 0 && data.length < 2000000, 'invalid_proof_bytes');
      writeFileSync(join(location, doc.id + '-page-' + doc.proofPages[index] + '.png'), data, { mode: 0o600 }); proofs.push({ page: doc.proofPages[index], sha256: hash(data), bytes: data.length });
    }
    documents.push({ id: doc.id, title: doc.title, name: doc.name, format: doc.format, size: doc.size, sha256: doc.sha256, downloadSHA256: hash(bytes), deliveredMatches: true, review: doc.review, contentQuality: doc.contentQuality, visualReview: doc.visualReview, qualityShortfalls: doc.qualityShortfalls, proofs, originalPath });
  }
  return { documents, retainedRecordCount: events.records?.length ?? 0 };
}
async function run(kind: Kind) {
  const recoveredGuides = process.argv.includes('--after-harness-fix');
  if (recoveredGuides) {
    fact(kind === 'pdf', 'bounded_pdf_harness_correction_only');
    const previous = JSON.parse(readFileSync(new URL('artifact-20261115-pdf-outcome.json', publicDirectory), 'utf8'));
    fact(previous.issue === 'cached_skill_provenance_unconfirmed' && previous.stopConfirmed === true && previous.documents?.length === 0 && previous.completed === false, 'previous_pdf_stop_and_zero_delivery_required');
  }
  const windowsill = process.argv.includes('--windowsill-pdf-scope');
  fact(!(windowsill && recoveredGuides) && !(freshFilePass && (windowsill || recoveredGuides)), 'one_explicit_acceptance_scope_required');
  if (windowsill) {
    fact(kind === 'pdf', 'windowsill_pdf_scope_only');
    const prior = JSON.parse(readFileSync(new URL('artifact-20261115-pdf-verified-guide-outcome.json', publicDirectory), 'utf8'));
    fact(prior.requestID === '1e6b78e7-ffeb-425a-90f0-df24b4afe109' && prior.stopConfirmed === true && prior.documents?.length === 0, 'prior_pdf_consumed_and_stopped_required');
  }
  const ask = windowsill ? 'Create and deliver a new two-page PDF titled Sunny Windowsill Herbs, a practical beginner guide to basil, rosemary and thyme grown in containers. Page 1: explain the light, watering, drainage and harvesting needs of each of these three herbs in separate concise sections. Page 2: include a concrete Monday-through-Sunday care checklist, a brief protective-care tip for cold nights and extreme heat, and a short troubleshooting section for yellow leaves and soggy soil. Use an original clean botanical editorial layout with legible type, clear headings and comfortable margins. This is a new guide with this exact scope, not retrieval or repair of any earlier artifact. Deliver the actual PDF, not its source.' : freshFilePass ? freshAsks[kind] : asks[kind];
  const stem = kind + (freshFilePass ? '-fresh-file-pass' : windowsill ? '-windowsill-new-guide' : recoveredGuides ? '-verified-guide' : '');
  fact(expectedBuild && /^[a-f0-9]{64}$/.test(expectedBuild), 'explicit_expected_build_required');
  const durableIntent = new URL('artifact-20261115-' + stem + '-intent.json', publicDirectory);
  const location = join(directory, stem);
  fact(!existsSync(durableIntent) && !existsSync(location), 'artifact_intent_consumed_no_replay');
  const account = load(), capabilities = await checked(account, '/knot/shell/capabilities');
  fact(capabilities.ok && capabilities.principal === 'whisper', 'capability_identity_mismatch');
  mkdirSync(location, { mode: 0o700 });
  const started = Date.now(), requestID = randomUUID(), conversationID = randomUUID(), sourceMessageID = randomUUID();
  const identity = { kind, backend, accountID: account.accountID, workspaceID: account.workspaceID, requestID, taskID: requestID, conversationID, sourceMessageID, expectedBuild, startedAt: new Date(started).toISOString() };
  const intent = { ...identity, ask, noAutomaticRetry: true, noHistoricalReplay: true, syntheticOnly: true, modelConsent: 'default_cloud_routed_only', documentConsent: 'knot_ai_consent_v4' };
  save(durableIntent.pathname, intent, true); save(join(location, 'intent.json'), intent, true); emit({ status: 'fresh_once_intent_consumed', ...identity });
  const aborter = new AbortController(), seen = new Set<string>(), outstanding = new Map<string, Data>();
  const provenance = new AcceptanceSkillProvenance({ accountID: account.accountID, workspaceID: account.workspaceID });
  // Import only actual completed ORIGINAL reads from this new synthetic account's
  // first turn. A cache may refer across conversations; it cannot seed itself.
  if (kind !== 'md') {
    const priorLocation = join(directory, freshFilePass ? 'md-fresh-file-pass' : 'md');
    const prior = JSON.parse(readFileSync(join(priorLocation, 'outcome.json'), 'utf8'));
    fact(prior.accountID === account.accountID && prior.workspaceID === account.workspaceID && prior.backend === backend && prior.stopConfirmed === true, 'exact_synthetic_original_read_scope_required');
    for (const execution of prior.executions) {
      if (execution.cached || execution.status !== 'completed') continue;
      const proposal = JSON.parse(readFileSync(join(priorLocation, execution.proposalID + '-proposal.json'), 'utf8'));
      const original = JSON.parse(readFileSync(join(priorLocation, execution.proposalID + '-result.json'), 'utf8'));
      fact(!original.cachedData, 'cache_cannot_seed_provenance');
      provenance.remember(proposal, original, prior);
    }
  }
  let pending = Promise.resolve(), issue: string | undefined, completed = false, workIncomplete = false, reply = '', stopConfirmed = true, sequence = 0;
  const executions: Data[] = [];
  const stop = async () => { aborter.abort(); for (const p of outstanding.values()) { try { const r = await checked(account, '/knot/shell/cancel', { bot: 'main', conversationID, proposalID: p.id }); save(join(location, p.id + '-cancel.json'), r); if (!r.terminationConfirmed) stopConfirmed = false; } catch { stopConfirmed = false; } } };
  const execute = async (p: Data) => {
    fact(!aborter.signal.aborted && p.bot === 'main' && p.conversationID === conversationID && p.taskID === requestID && p.sourceMessageID === sourceMessageID && /^[a-f0-9-]{36}$/.test(p.id) && !seen.has(p.id) && typeof p.command === 'string', 'owned_proposal_mismatch_no_replay');
    fact(seen.size < 35 && Date.now() - started < 900000, 'acceptance_work_ceiling');
    seen.add(p.id); outstanding.set(p.id, p); save(join(location, p.id + '-proposal.json'), p);
    const response = await request(account, '/knot/shell/execute', { bot: 'main', conversationID, proposalID: p.id, executionVersion: 'knot_shell_automatic_v1', command: p.command, timeoutMs: p.timeoutMs }, 160000);
    fact(response.ok, 'execute_http_' + response.status); let result = await response.json() as Data;
    assertAcceptanceIdentity(p, result, identity); let cached = provenance.acceptCache(p, result, identity);
    const until = Date.now() + 20000;
    while (!cached && result.sessionID && !(result.terminationConfirmed && result.commandReceipt && result.outputComplete && !result.truncated) && result.status !== 'cancelled' && Date.now() < until) {
      await new Promise(resolve => setTimeout(resolve, 700)); result = await checked(account, '/knot/shell/status', { bot: 'main', conversationID, proposalID: p.id }); assertAcceptanceIdentity(p, result, identity); cached = provenance.acceptCache(p, result, identity);
    }
    save(join(location, p.id + '-result.json'), result);
    fact(result.terminationConfirmed && (!result.sessionID || result.outputComplete && !result.truncated && (cached || result.commandReceipt)), 'execution_unconfirmed_no_replay');
    if (!cached && result.sessionID) fact(result.providerReceipt?.user_id === account.workspaceID && result.providerReceipt?.session_id === result.sessionID, 'dedicated_workspace_receipt_mismatch');
    if (!cached) provenance.remember(p, result, identity);
    const summary = { proposalID: p.id, operation: p.operation, documentStage: p.documentInvocation?.stage, status: result.status, exitCode: result.exitCode, terminationConfirmed: result.terminationConfirmed, outputComplete: result.outputComplete, cached, stdoutSHA256: hash(result.stdout ?? '') };
    executions.push(summary); outstanding.delete(p.id); emit(summary);
  };
  try {
    const response = await request(account, '/knot/chat/stream', { requestID, bot: 'main', conversationID, sourceMessageID, sourceCreatedAt: started, consentVersion: 'knot_ai_consent_v4', message: ask, healthContext: '', history: [], isWebQuery: false, sharedConversation: false, timezone: 'UTC', foregroundTurnVersion: 'knot_foreground_turn_v1', workProgressVersion: 'knot_work_progress_v1', documentProgramVersion: 'knot_document_program_v3', taskExperienceVersion: 'knot_task_experience_v1', clarificationVersion: 'knot_clarification_v1' }, 945000, aborter.signal);
    fact(response.ok && response.body, 'stream_http_' + response.status); const reader = response.body.getReader(), decoder = new TextDecoder(); let buffer = '';
    try { for (;;) { const part = await reader.read(); if (part.done) break; buffer += decoder.decode(part.value, { stream: true }); let at: number;
      while ((at = buffer.indexOf('\n\n')) >= 0) { const packet = buffer.slice(0, at); buffer = buffer.slice(at + 2); const text = packet.split('\n').filter(line => line.startsWith('data:')).map(line => line.slice(5).trimStart()).join('\n'); if (!text) continue;
        const frame = JSON.parse(text); fact(frame.requestID === requestID && frame.sequence === ++sequence, 'stream_identity_or_sequence_mismatch');
        appendFileSync(join(location, 'frames.jsonl'), JSON.stringify({ ...frame, elapsedMs: Date.now() - started }) + '\n', { mode: 0o600 });
        if (frame.type === 'shell_proposal') pending = pending.then(() => execute(frame.proposal)).catch(async e => { issue ??= safe(e); await stop(); });
        if (frame.type === 'complete') { completed = true; workIncomplete = frame.workIncomplete === true; reply = frame.reply ?? ''; if (workIncomplete) issue ??= frame.reason ?? 'work_incomplete'; }
        if (['error', 'rejected', 'document_work_unavailable'].includes(frame.type)) issue ??= frame.reason ?? frame.error ?? frame.type;
      }
    } fact(!buffer.trim(), 'incomplete_stream_frame'); } finally { reader.releaseLock(); }
  } catch (e) { issue ??= safe(e); await stop(); }
  await pending; if (outstanding.size) await stop();
  let retained: Data = {}; try { retained = await collect(account, identity, location); } catch (e) { issue ??= safe(e); }
  const result = { ...identity, elapsedMs: Date.now() - started, completed, workIncomplete, issue: issue ?? null, stopConfirmed, executions, ...retained, frameCount: sequence, chatSubmissions: 1, directSidecarCalls: 0, personalAccountAccessed: false };
  save(join(location, 'reply.json'), { reply }); save(join(location, 'outcome.json'), result); save(new URL('artifact-20261115-' + stem + '-outcome.json', publicDirectory).pathname, result, true); emit(result);
  if (issue || !completed || workIncomplete || !retained.documents?.length) process.exitCode = 2;
}
async function main() {
  if (process.argv.includes('--prepare')) return prepare();
  if (process.argv.includes('--refresh-synthetic-session')) {
    const account = JSON.parse(readFileSync(accountPath, 'utf8'));
    const key = process.env.KNOT_ACCEPTANCE_SUPABASE_SERVICE_ROLE_KEY;
    fact(key && account.projectRef === projectRef && account.accountID === '4e02c8a2-f40d-46d1-b6d3-68304a126918' && account.workspaceID === 'whisper-' + account.accountID, 'exact_synthetic_identity_required');
    const user = await auth('/auth/v1/admin/users/' + account.accountID, key);
    fact(user.id === account.accountID && /^knot-artifact-qa-[a-f0-9-]+@example\.com$/.test(user.email) && user.user_metadata?.artifact_acceptance_20261115 === true && user.user_metadata?.dedicated_knot_acceptance === true, 'synthetic_metadata_mismatch');
    const link = await auth('/auth/v1/admin/generate_link', key, { type: 'magiclink', email: user.email });
    save(join(directory, 'synthetic-link-response.json'), link);
    const linkedID = link.user?.id ?? link.id, tokenHash = link.properties?.hashed_token ?? link.hashed_token;
    fact(linkedID === account.accountID && typeof tokenHash === 'string' && tokenHash.length > 20, 'synthetic_link_identity_mismatch');
    const session = await auth('/auth/v1/verify', key, { type: 'magiclink', token_hash: tokenHash });
    fact(session.user?.id === account.accountID && session.access_token, 'synthetic_refreshed_identity_mismatch');
    save(accountPath, { ...account, accessToken: session.access_token });
    emit({ status: 'exact_synthetic_session_refreshed', credentialsPrinted: false, emailSent: false });
    return;
  }
  if (process.argv.includes('--inspect-pdf-findings') || process.argv.includes('--inspect-windowsill-findings')) {
    const windowsill = process.argv.includes('--inspect-windowsill-findings');
    const account = load(), location = join(directory, windowsill ? 'pdf-windowsill-new-guide' : 'pdf-verified-guide');
    const identity = JSON.parse(readFileSync(join(location, 'intent.json'), 'utf8'));
    fact(identity.accountID === account.accountID && identity.workspaceID === account.workspaceID && identity.requestID === (windowsill ? '3ed70d56-248b-4f04-a7fa-9475802f71f2' : '1e6b78e7-ffeb-425a-90f0-df24b4afe109'), 'exact_pdf_diagnostic_scope_required');
    const result = await checked(account, '/knot/shell/events', { bot: 'main', conversationID: identity.conversationID, proposalID: windowsill ? 'f7d3edf1-0941-4992-bf82-b9054c13c518' : 'd8e1079a-9f08-436f-99cc-be57d497d11d' });
    fact(result.records?.every((r: Data) => r.taskID === identity.requestID && r.sourceMessageID === identity.sourceMessageID), 'diagnostic_record_identity_mismatch');
    save(join(location, 'content-findings-inspection.json'), result);
    emit({ status: 'read_only_owned_pdf_findings', events: result.events?.filter((e: Data) => /document_(?:content|proof|visual)/.test(e.kind)) });
    return;
  }
  const kind = flag('--run') ?? flag('--collect'); fact(kind && Object.hasOwn(asks, kind), 'explicit_artifact_kind_required');
  if (flag('--run')) return run(kind as Kind);
  const location = join(directory, kind + (freshFilePass ? '-fresh-file-pass' : '')), identity = JSON.parse(readFileSync(join(location, 'intent.json'), 'utf8')); const result = await collect(load(), identity, location); save(join(location, 'collected.json'), result); emit(result);
}
main().catch(e => { emit({ status: 'blocked_no_automatic_replay', reason: safe(e) }); process.exitCode = 2; });
