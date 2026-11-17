// Explicit fresh isolated owned-turn acceptance; never reuses a consumed scope.
// Credentials remain only in memory. Private observations go outside the project.
import { mkdirSync, existsSync, readFileSync, writeFileSync, appendFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID, randomBytes, createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { knotSourceBuildSHA256 } from '../functions/knot-source-build';
type Data = Record<string, any>;
const scope = process.argv[2];
if (!/^--fresh-[a-z0-9-]{1,32}$/.test(scope ?? '')) throw new Error('explicit_new_scope_required');
const name = 'knot-owned-pdf-20261116-' + scope.slice(8);
const privateRoot = join(tmpdir(), name), resultPath = new URL('../deliveries/' + name + '-outcome.json', import.meta.url).pathname;
if (existsSync(privateRoot) || existsSync(resultPath)) throw new Error('scope_consumed_no_replay');
mkdirSync(privateRoot, { mode: 0o700 });
const save = (name: string, value: unknown) => writeFileSync(join(privateRoot, name), JSON.stringify(value, null, 2), { mode: 0o600, flag: 'wx' });
const fact: (value: unknown, reason: string) => asserts value = (value, reason) => { if (!value) throw new Error(reason); };
const digest = (bytes: Uint8Array | string) => createHash('sha256').update(bytes).digest('hex');
const backend = 'https://newest-whisper-with-knot-clone-t6ui3ur-backend.rork.app', authBase = 'https://uryyyegnbtlmyhqlgndy.supabase.co';
const key = process.env.KNOT_ACCEPTANCE_SUPABASE_SERVICE_ROLE_KEY; fact(key, 'admin_key_unavailable');
const startedAt = Date.now(), taskID = randomUUID(), conversationID = randomUUID();
const outcome: Data = { scope: name, taskID, conversationID, expectedBuild: knotSourceBuildSHA256, syntheticOnly: true, ownerAccessed: false, noReplay: true, startedAt: new Date(startedAt).toISOString(), passed: false };
save('intent.json', outcome);
let token = '', admitted = false;
async function auth(path: string, body: unknown) {
  const r = await fetch(authBase + path, { method: 'POST', redirect: 'error', headers: { apikey: key!, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal: AbortSignal.timeout(25000) });
  fact(r.ok, 'auth_http_' + r.status); return await r.json() as Data;
}
async function request(path: string, body?: unknown) {
  const r = await fetch(backend + path, { method: body === undefined ? 'GET' : 'POST', redirect: 'error', headers: { 'X-Whisper-Authorization': 'Bearer ' + token, 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(30000) });
  fact(r.headers.get('X-Knot-Worker-Build') === knotSourceBuildSHA256, 'worker_build_mismatch');
  const actor = r.headers.get('X-Knot-Actor-Build'); fact(!actor || actor === knotSourceBuildSHA256, 'actor_build_mismatch');
  fact(r.ok, 'managed_http_' + r.status); return r;
}
async function api(path: string, body?: unknown) { return await (await request(path, body)).json() as Data; }
try {
  const email = `knot-qa-${randomUUID()}@example.com`, password = randomBytes(32).toString('base64url');
  const user = await auth('/auth/v1/admin/users', { email, password, email_confirm: true, user_metadata: { dedicated_knot_acceptance: true, fresh_owned_pdf_20261116: true } });
  const session = await auth('/auth/v1/token?grant_type=password', { email, password });
  fact(user.id === session.user?.id && session.user?.user_metadata?.fresh_owned_pdf_20261116 === true, 'fresh_identity_mismatch'); token = session.access_token;
  outcome.accountID = user.id; outcome.workspaceID = 'whisper-' + user.id;
  const index = await api('/knot/turns'); fact(typeof index.approvalEpoch === 'string' && index.tasks.length === 0, 'fresh_actor_required');
  const ask = 'Create and deliver a new actual two-page PDF titled Rainy Day Reading Plan. Page one: five practical reading-nook preparation tasks and a short book-selection checklist. Page two: Friday, Saturday and Sunday reading schedule. Use warm cream and dark ink, considered typography, comfortable margins and concise readable text. This is new authoring, not retrieval or repair. Deliver the actual PDF, not Markdown or an explanation.';
  const submission = { requestID: taskID, sourceMessageID: taskID, sourceCreatedAt: startedAt, conversationID, bot: 'main', backgroundApprovalEpoch: index.approvalEpoch, consentVersion: 'knot_ai_consent_v4', message: ask, healthContext: '', history: [], isWebQuery: false, sharedConversation: false, timezone: 'UTC', foregroundTurnVersion: 'knot_foreground_turn_v1', workProgressVersion: 'knot_work_progress_v1', documentProgramVersion: 'knot_document_program_v3', taskExperienceVersion: 'knot_task_experience_v1', clarificationVersion: 'knot_clarification_v1' };
  save('submission.json', submission);
  // Exactly one POST; any uncertain admission is quarantined, never resubmitted.
  admitted = true;
  const receipt = await api('/knot/turns', submission); fact(receipt.task?.id === taskID, 'admission_identity_mismatch');
  let after = 0, terminal = false; const labels: Data[] = [];
  while (Date.now() - startedAt < 960000) {
    const page = await api('/knot/turns/' + taskID + '?after=' + after);
    fact(page.task?.id === taskID && page.task.conversationID === conversationID && page.task.sourceMessageID === taskID && page.next >= after, 'poll_identity_mismatch');
    appendFileSync(join(privateRoot, 'pages.jsonl'), JSON.stringify({ observedAt: new Date().toISOString(), ...page }) + '\n', { mode: 0o600 });
    if (page.currentActivity) labels.push({ observedAt: new Date().toISOString(), ...page.currentActivity });
    for (const frame of page.events) fact(frame.requestID === taskID && frame.sequence === ++after, 'frame_identity_mismatch');
    fact(after === page.next, 'cursor_mismatch');
    if (page.terminal && !page.hasMore) { outcome.terminal = page; terminal = true; break; }
    if (!page.hasMore) await new Promise(resolve => setTimeout(resolve, 1200));
  }
  outcome.labels = labels;
  fact(terminal, 'owned_deadline_without_terminal');
  const events = await api('/knot/shell/events', { bot: 'main', conversationID }); save('events.json', events);
  outcome.failures = events.activities?.filter((a: Data) => /rejected|unavailable/.test(a.kind));
  const docs = (events.documents ?? []).filter((d: Data) => d.sourceMessageID === taskID);
  fact(docs.length === 1 && docs[0].format === 'pdf', 'fresh_pdf_capture_missing');
  const doc = docs[0], response = await request('/knot/shell/documents', { bot: 'main', conversationID, documentID: doc.id, action: 'file' });
  const bytes = new Uint8Array(await response.arrayBuffer());
  fact(digest(bytes) === doc.sha256 && bytes.length === doc.size && response.headers.get('X-Knot-SHA256') === doc.sha256 && response.headers.get('Content-Type')?.includes('application/pdf'), 'original_delivery_byte_mismatch');
  const original = new URL('../deliveries/' + name + '-original.pdf', import.meta.url).pathname; fact(!existsSync(original), 'delivery_collision'); writeFileSync(original, bytes, { flag: 'wx' });
  outcome.document = { ...doc, originalPath: original, downloadedSHA256: digest(bytes), visualInspection: 'pending' };
  const inspectionRoot = join(privateRoot, 'independent');
  const inspected = spawnSync('python3', [new URL('./inspect-knot-pdf-20261116.py', import.meta.url).pathname, original, inspectionRoot, '--require-page-assignment'], { encoding: 'utf8', env: { ...process.env, PYTHONPATH: join(tmpdir(), 'knot-pdf-inspection-20261116') } });
  if (existsSync(join(inspectionRoot, 'inspection.json'))) outcome.independentInspection = JSON.parse(readFileSync(join(inspectionRoot, 'inspection.json'), 'utf8'));
  fact(inspected.status === 0 && outcome.independentInspection?.sha256 === doc.sha256, 'independent_content_or_page_assignment_unconfirmed');
  const history = await api('/knot/conversations/' + conversationID); save('history.json', history);
  fact(Array.isArray(history.messages) && history.messages.some((m: Data) => m.id === taskID && m.text === ask), 'source_history_unconfirmed');
  fact(outcome.terminal.result?.reply === '', 'card_only_terminal_unconfirmed');
  fact(!history.messages.some((m: Data) => m.id === outcome.terminal.task.replyID), 'card_only_history_has_reply_bubble');
  outcome.cardOnlyCompletion = true;
  const retained = await api('/knot/shell/events', { bot: 'main', conversationID });
  fact(retained.documents?.some((d: Data) => d.id === doc.id && d.sha256 === doc.sha256 && d.sourceMessageID === taskID), 'durable_capture_history_unconfirmed');
  outcome.historyRead = true; outcome.document = { ...doc, originalPath: original, downloadedSHA256: digest(bytes), independentTextAndPages: true, localRender: true, visualInspection: 'pending' };
  fact(outcome.terminal.task.state === 'completed', 'degraded_terminal_not_acceptance');
  outcome.automatedChecksPassed = true;
  // Human visual review remains separate; do not manufacture an overall pass.
  outcome.passed = false; outcome.awaitingVisualReview = true;
} catch (error) {
  outcome.issue = error instanceof Error && /^[a-z0-9_]+$/.test(error.message) ? error.message : 'unconfirmed_failure';
  if (admitted) { try { outcome.stopAcknowledgment = await api('/knot/turns/' + taskID + '/cancel', {}); } catch { outcome.stopAcknowledgment = 'unconfirmed'; } }
  process.exitCode = 2;
} finally {
  outcome.endedAt = new Date().toISOString(); outcome.elapsedMs = Date.now() - startedAt;
  save('outcome.json', outcome); writeFileSync(resultPath, JSON.stringify(outcome, null, 2) + '\n', { flag: 'wx' }); console.log(JSON.stringify(outcome));
}
