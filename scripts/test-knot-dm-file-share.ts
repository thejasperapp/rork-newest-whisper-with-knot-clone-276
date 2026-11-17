// DM file-sharing acceptance with two dedicated QA identities only (never a
// personal account). Credentials stay in private OS temp storage, never printed.
//   rork env run -- bun scripts/test-knot-dm-file-share.ts --prepare-recipient
//   rork env run -- bun scripts/test-knot-dm-file-share.ts --login
//   bun scripts/test-knot-dm-file-share.ts --make "<file request>"     (sender asks Knot for a file)
//   bun scripts/test-knot-dm-file-share.ts --share <conversationID>    (send every file in that chat by DM, then open each as the recipient)
import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { randomBytes, randomUUID, createHash } from 'node:crypto';

const backend = 'https://newest-whisper-with-knot-clone-t6ui3ur-backend.rork.app';
const projectRef = 'uryyyegnbtlmyhqlgndy';
const database = `https://${projectRef}.supabase.co`;
const senderDir = join(tmpdir(), 'knot-native-ui-mayokn2749ag072e3uvbh-20261114');
const recipientDir = join(tmpdir(), 'knot-dm-share-recipient-mayokn2749ag072e3uvbh');
const senderID = 'ae19aba1-0055-448c-9c70-1e61036908a3';
const recipientID = 'a562fe0f-8340-4d85-b883-ede93656f9a7';
const log = (step: string, data: unknown = {}) => console.log(JSON.stringify({ at: new Date().toISOString(), step, ...data as object }));
function fact(ok: unknown, reason: string): asserts ok { if (!ok) throw new Error(reason); }
type Session = { accountID: string; accessToken: string };
const session = (dir: string) => JSON.parse(readFileSync(join(dir, 'api-session.json'), 'utf8')) as Session;
const anon = () => { const key = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY; fact(key, 'anon_key_required'); return key; };

async function login(dir: string, expected?: string) {
  const state = JSON.parse(readFileSync(join(dir, 'account.json'), 'utf8')) as { email: string; password: string; accountID: string };
  fact(/@example\.com$/.test(state.email) && (!expected || state.accountID === expected), 'dedicated_identity_required');
  const response = await fetch(`${database}/auth/v1/token?grant_type=password`, { method: 'POST', headers: { apikey: anon(), 'Content-Type': 'application/json' }, body: JSON.stringify({ email: state.email, password: state.password }) });
  fact(response.ok, 'login_http_' + response.status);
  const value = await response.json() as { access_token: string; user: { id: string } };
  fact(value.user.id === state.accountID, 'login_identity_mismatch');
  writeFileSync(join(dir, 'api-session.json'), JSON.stringify({ accountID: state.accountID, accessToken: value.access_token }), { mode: 0o600 });
  log('login', { accountID: state.accountID });
}

async function knot(s: Session, path: string, body?: unknown) {
  const response = await fetch(backend + path, { method: body === undefined ? 'GET' : 'POST', headers: { 'X-Whisper-Authorization': 'Bearer ' + s.accessToken, 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
  const bytes = new Uint8Array(await response.arrayBuffer());
  let json: any; try { json = JSON.parse(new TextDecoder().decode(bytes)); } catch { json = undefined; }
  return { status: response.status, json, bytes };
}
async function rest(s: Session, path: string, init: RequestInit = {}) {
  const response = await fetch(database + '/rest/v1' + path, { ...init, headers: { apikey: anon(), Authorization: 'Bearer ' + s.accessToken, 'Content-Type': 'application/json', Prefer: 'return=representation', ...(init.headers ?? {}) } });
  return { status: response.status, text: await response.text() };
}

async function main() {
  const mode = process.argv[2];
  if (mode === '--prepare-recipient') {
    const key = process.env.KNOT_ACCEPTANCE_SUPABASE_SERVICE_ROLE_KEY;
    fact(key, 'dedicated_admin_credential_unavailable');
    mkdirSync(recipientDir, { recursive: true, mode: 0o700 });
    fact(!existsSync(join(recipientDir, 'account.json')), 'recipient_already_prepared_no_replay');
    const state = { email: `knot-dm-share-${randomUUID()}@example.com`, password: randomBytes(32).toString('base64url') };
    writeFileSync(join(recipientDir, 'account.json'), JSON.stringify(state), { mode: 0o600, flag: 'wx' });
    const response = await fetch(`${database}/auth/v1/admin/users`, { method: 'POST', headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ email: state.email, password: state.password, email_confirm: true, user_metadata: { dedicated_knot_acceptance: true, full_name: 'Knot QA Friend' } }) });
    fact(response.ok, 'recipient_create_http_' + response.status);
    const user = await response.json() as { id: string };
    writeFileSync(join(recipientDir, 'account.json'), JSON.stringify({ ...state, accountID: user.id }), { mode: 0o600 });
    log('recipient_created', { accountID: user.id, emailSent: false });
    return;
  }
  if (mode === '--recover') {
    // Temp storage was cleared: rotate ONLY the two dedicated QA identities'
    // passwords. Refuses any account that is not a dedicated @example.com QA user.
    const key = process.env.KNOT_ACCEPTANCE_SUPABASE_SERVICE_ROLE_KEY;
    fact(key, 'dedicated_admin_credential_unavailable');
    for (const [dir, id] of [[senderDir, senderID], [recipientDir, recipientID]] as const) {
      const headers = { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };
      const current = await fetch(`${database}/auth/v1/admin/users/${id}`, { headers });
      fact(current.ok, 'qa_lookup_http_' + current.status);
      const user = await current.json() as { id: string; email?: string };
      fact(user.id === id && typeof user.email === 'string' && /@example\.com$/.test(user.email), 'dedicated_identity_required');
      const password = randomBytes(32).toString('base64url');
      const updated = await fetch(`${database}/auth/v1/admin/users/${id}`, { method: 'PUT', headers, body: JSON.stringify({ password }) });
      fact(updated.ok, 'qa_rotate_http_' + updated.status);
      mkdirSync(dir, { recursive: true, mode: 0o700 });
      writeFileSync(join(dir, 'account.json'), JSON.stringify({ email: user.email, password, accountID: id }), { mode: 0o600 });
      log('qa_identity_recovered', { accountID: id });
    }
    return;
  }
  if (mode === '--login') {
    await login(senderDir, senderID); await login(recipientDir);
    // Each QA identity allows the other to contact it (own-row RLS writes only).
    const a = session(senderDir), b = session(recipientDir);
    for (const [me, other] of [[a, b], [b, a]] as const) {
      const r = await rest(me, '/whisper_contact_permissions?on_conflict=recipient_id,sender_id', { method: 'POST', headers: { Prefer: 'resolution=merge-duplicates,return=minimal' }, body: JSON.stringify({ recipient_id: me.accountID, sender_id: other.accountID, allowed: true }) });
      log('contact_permission', { recipient: me.accountID, status: r.status, error: r.status >= 300 ? r.text.slice(0, 200) : undefined });
    }
    return;
  }
  const a = session(senderDir);
  fact(a.accountID === senderID, 'dedicated_qa_identity_required');
  if (mode === '--make') {
    const index = await knot(a, '/knot/turns');
    const source = randomUUID(), conversation = randomUUID();
    const submitted = await knot(a, '/knot/turns', {
      requestID: source, consentVersion: 'knot_ai_consent_v4', message: process.argv[3], bot: 'main',
      healthContext: `CURRENT DEVICE DATE: ${new Date().toISOString()}; TIME ZONE: UTC.`, history: [], isWebQuery: false, sharedConversation: false, timezone: 'UTC',
      conversationID: conversation, sourceMessageID: source, sourceCreatedAt: Date.now(),
      taskModelConsentVersion: 'knot_task_models_v1', taskExperienceVersion: 'knot_task_experience_v1',
      foregroundTurnVersion: 'knot_foreground_turn_v1', workProgressVersion: 'knot_work_progress_v1', backgroundApprovalEpoch: index.json?.approvalEpoch,
      // Mirror the shipping iOS request so document turns take the same path.
      documentProgramVersion: 'knot_document_program_v3', documentReviewConsentVersion: 'knot_document_review_v1',
      foregroundBrowserVersion: 'knot_native_browser_v1', browserPreviewVersion: 'knot_browser_preview_v1', clarificationVersion: 'knot_clarification_v1',
      reactionVersion: 'knot_reactions_v1', browserContinuationVersion: 'knot_browser_continuation_v1',
    });
    log('submitted', { status: submitted.status, conversation, task: source });
    // Sample the server-driven pill every 2 s, as the iOS header would see it.
    let shown: string | null | undefined;
    for (let i = 0; i < 450; i++) {
      await Bun.sleep(2000);
      const turn = await knot(a, `/knot/turns/${source}?after=0`);
      const label = turn.json?.currentActivity?.label ?? null;
      if (label !== shown) { log('pill', { label }); shown = label; }
      if (turn.json?.terminal) {
        log('timeline', { activityTimeline: turn.json.activityTimeline ?? null });
        log('finished', { state: turn.json.task?.state, reply: String(turn.json.result?.reply ?? '').slice(0, 300) });
        break;
      }
    }
    const docs = await knot(a, '/knot/shell/documents', { action: 'list', bot: 'main', conversationID: conversation });
    log('documents', { conversation, files: (docs.json?.documents ?? []).map((d: any) => ({ name: d.name, format: d.format, size: d.size })) });
    return;
  }
  if (mode === '--capabilities') {
    // Tool catalog shape only (names, routes, request fields); no secrets.
    const caps = await knot(a, '/knot/shell/capabilities');
    for (const t of caps.json?.tools ?? []) console.log(JSON.stringify({ name: t.name, method: t.method, path: t.path, request: t.request, returns: String(t.returns).slice(0, 160) }));
    log('capabilities', { status: caps.status, tools: caps.json?.tools?.length, limits: caps.json?.limits });
    return;
  }
  if (mode === '--peek') {
    // Content-light event trail of a finished QA turn (types + safe detail).
    const events: any[] = []; let turn: any, after = 0;
    for (let page = 0; page < 10; page++) {
      turn = await knot(a, `/knot/turns/${process.argv[3]}?after=${after}`);
      events.push(...(turn.json?.events ?? []));
      if (!turn.json?.hasMore) break; after = turn.json.next;
    }
    const quiet = /model_transport|^accepted$|shell_review_ready|work_phase|tool_selection_attempt|document_program_attempt|document_program_started/;
    for (const e of events) {
      const kind = e.activity?.kind ?? e.type;
      if (quiet.test(kind)) continue;
      if (e.type === 'shell_proposal') { console.log(JSON.stringify({ n: e.sequence, kind, proposal: e.proposal?.id, tool: e.proposal?.tool, title: e.proposal?.title })); continue; }
      const d = e.activity?.detail ?? {};
      console.log(JSON.stringify({ n: e.sequence, kind, reason: e.reason ?? d.reason, fields: d.fields, tool: d.tool, phase: d.selectionPhase, exit: d.terminationExit, check: d.check, branch: d.branch, sha: d.programSHA256?.slice(0, 8) }));
    }
    log('peek', { state: turn?.json?.task?.state, events: events.length, currentActivity: turn?.json?.currentActivity ?? null, activityTimeline: turn?.json?.activityTimeline ?? null });
    return;
  }
  if (mode === '--record') {
    // Read-only shell record of a QA conversation (never dispatches or replays).
    const conversation = process.argv[3];
    const res = await knot(a, '/knot/shell/events', { bot: 'main', conversationID: conversation });
    for (const r of res.json?.records ?? []) console.log(JSON.stringify({ proposal: r.spec?.id, tool: r.spec?.tool, title: r.spec?.title, command: String(r.spec?.command ?? '').slice(0, 1200), status: r.result?.status, exitCode: r.result?.exitCode, outputComplete: r.result?.outputComplete, terminationConfirmed: r.result?.terminationConfirmed, stdout: String(r.result?.stdout ?? '').slice(-600), stderr: String(r.result?.stderr ?? '').slice(-300) }));
    log('record', { status: res.status, records: res.json?.records?.length ?? 0, error: res.json?.error });
    return;
  }
  if (mode === '--share') {
    const b = session(recipientDir), conversation = process.argv[3];
    const docs = await knot(a, '/knot/shell/documents', { action: 'list', bot: 'main', conversationID: conversation });
    let failures = 0;
    for (const doc of docs.json?.documents ?? []) {
      const messageID = randomUUID();
      const prepared = await knot(a, '/knot/artifacts/prepare', { messageID, recipientID: b.accountID, bot: 'main', conversationID: conversation, documentID: doc.id });
      if (prepared.status !== 200) { failures++; log('prepare_failed', { name: doc.name, status: prepared.status, error: prepared.json?.error }); continue; }
      const thread = createHash('sha256').update([a.accountID, b.accountID].sort().join('|')).digest('hex').slice(0, 32);
      const threadID = [thread.slice(0, 8), thread.slice(8, 12), thread.slice(12, 16), thread.slice(16, 20), thread.slice(20)].join('-');
      const sent = await rest(a, '/whisper_messages', { method: 'POST', body: JSON.stringify({ id: messageID, from_user_id: a.accountID, to_user_id: b.accountID, from_username: 'knotqa', to_username: 'knotqafriend', thread_id: threadID, body: prepared.json.body }) });
      if (sent.status >= 300) { failures++; log('dm_insert_failed', { name: doc.name, status: sent.status, error: sent.text.slice(0, 300) }); continue; }
      const resolved = await knot(b, '/knot/artifacts/resolve', { messageID });
      const file = await knot(b, '/knot/artifacts/resource', { messageID, action: 'file' });
      const hash = createHash('sha256').update(file.bytes).digest('hex');
      const ok = resolved.status === 200 && file.status === 200 && hash === doc.sha256;
      if (!ok) failures++;
      log(ok ? 'shared_ok' : 'shared_failed', { name: doc.name, format: doc.format, resolve: resolved.status, resolveError: resolved.json?.error, sender: resolved.json?.senderName, file: file.status, fileError: file.json?.error, sameBytes: hash === doc.sha256, publicDocument: resolved.json?.document });
    }
    log(failures ? 'NOT_PASSED' : 'PASS', { files: docs.json?.documents?.length ?? 0, failures });
    process.exitCode = failures ? 1 : 0;
    return;
  }
  fact(false, 'unknown_mode');
}
main().catch(error => { console.error(JSON.stringify({ status: 'blocked', reason: error instanceof Error ? error.message : 'unknown' })); process.exitCode = 2; });
