// Live synthetic acceptance only. Explicit fresh scope is consumed before I/O.
// Exactly one admission, memory-only credentials, read-only polling and Stop on
// failure. Never adopts/replays a command or touches the owner's workspace.
import { existsSync, mkdirSync, writeFileSync, appendFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID, randomBytes, createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { knotSourceBuildSHA256 } from '../functions/knot-source-build';
type Data = Record<string, any>;
const content = 'Title Balcony Herb Plan. Include Basil and Mint, practical setup steps, watering and harvesting advice, and a safety note to keep mint contained. Use concise but useful complete explanations.';
const data = 'Use exactly the three columns Plant, Containers, WeeklyWaterChecks and exactly these data rows: Basil,2,3 and Mint,1,4. No extra rows or columns.';
const cases: Record<string, { format: string; ask: string }> = {
  txt: { format: 'txt', ask: 'Create a new actual TXT file. ' + content },
  md: { format: 'md', ask: 'Create a new actual Markdown file, retaining headings and lists as Markdown. ' + content },
  html: { format: 'html', ask: 'Create a new actual self-contained HTML document, not an app or game, with no remote resources or active scripts. ' + content },
  csv: { format: 'csv', ask: 'Create a new actual CSV file. ' + data },
  json: { format: 'json', ask: 'Create a new actual JSON file containing exactly {"title":"Balcony Herb Plan","plants":[{"name":"Basil","containers":2,"weeklyWaterChecks":3},{"name":"Mint","containers":1,"weeklyWaterChecks":4}]}. Keep the numbers numeric and add no keys.' },
  docx: { format: 'docx', ask: 'Create a new actual Word file, not a PDF. ' + content },
  xlsx: { format: 'xlsx', ask: 'Create a new actual Excel file, not a PDF. Exactly one sheet named Balcony Herb Plan. Put headers in A1:C1 and the two data rows in A2:C3, numeric values as numeric cells and no formulas or other cells. ' + data },
  pptx: { format: 'pptx', ask: 'Create four new actual slides as one PowerPoint file, not a PDF. ' + content + ' Exactly four slides: title, setup, watering, harvesting. Use legible unclipped text.' },
  'pdf-forest': { format: 'pdf', ask: 'Create and deliver a new actual PDF, one or two pages, with forest green accents and comfortable typography. ' + content },
  'pdf-mono': { format: 'pdf', ask: 'Create and deliver a new actual PDF, one or two pages, in a monochrome black-and-white design. ' + content },
  'pdf-plain': { format: 'pdf', ask: 'Create and deliver a new actual explicitly plain PDF from complete Markdown source using house-v1 styling. ' + content },
  'pdf-guide': { format: 'pdf', ask: 'Create and deliver a new actual PDF using the guide@1.0.0 house template. ' + content },
  'pdf-report': { format: 'pdf', ask: 'Create and deliver a new actual PDF using the report@1.0.0 house template. ' + content },
  'pdf-letter': { format: 'pdf', ask: 'Create and deliver a new actual PDF using the letter@1.0.0 house template. ' + content },
};
const [scope, caseName] = process.argv.slice(2);
if (!/^--fresh-[a-z0-9-]{1,32}$/.test(scope ?? '') || !Object.hasOwn(cases, caseName ?? '')) throw new Error('explicit_fresh_scope_and_case_required');
const spec = cases[caseName], name = 'knot-format-matrix-20261116-' + scope.slice(8) + '-' + caseName;
const privateRoot = join(tmpdir(), name), outcomePath = new URL('../deliveries/' + name + '-outcome.json', import.meta.url).pathname;
if (existsSync(privateRoot) || existsSync(outcomePath)) throw new Error('scope_consumed_no_replay');
mkdirSync(privateRoot, { mode: 0o700 });
const save = (file: string, value: unknown) => writeFileSync(join(privateRoot, file), JSON.stringify(value, null, 2), { mode: 0o600, flag: 'wx' });
const fact: (value: unknown, reason: string) => asserts value = (value, reason) => { if (!value) throw new Error(reason); };
const digest = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');
const key = process.env.KNOT_ACCEPTANCE_SUPABASE_SERVICE_ROLE_KEY; fact(key, 'admin_key_unavailable');
const backend = 'https://newest-whisper-with-knot-clone-t6ui3ur-backend.rork.app', authBase = 'https://uryyyegnbtlmyhqlgndy.supabase.co';
const startedAt = Date.now(), taskID = randomUUID(), conversationID = randomUUID();
const outcome: Data = { scope: name, caseName, requestedFormat: spec.format, taskID, conversationID, expectedBuild: knotSourceBuildSHA256, syntheticOnly: true, ownerAccessed: false, noReplay: true, startedAt: new Date(startedAt).toISOString(), passed: false };
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
  const user = await auth('/auth/v1/admin/users', { email, password, email_confirm: true, user_metadata: { dedicated_knot_acceptance: true, fresh_format_matrix_20261116: true } });
  const session = await auth('/auth/v1/token?grant_type=password', { email, password });
  fact(user.id === session.user?.id && session.user?.user_metadata?.fresh_format_matrix_20261116 === true, 'fresh_identity_mismatch'); token = session.access_token;
  outcome.accountID = user.id;
  const index = await api('/knot/turns'); fact(typeof index.approvalEpoch === 'string' && index.tasks.length === 0, 'fresh_actor_required');
  const ask = spec.ask + ' This is new authoring, not retrieval or repair. Deliver the actual original-format file, not a chat explanation or substitute.';
  const submission = { requestID: taskID, sourceMessageID: taskID, sourceCreatedAt: startedAt, conversationID, bot: 'main', backgroundApprovalEpoch: index.approvalEpoch, consentVersion: 'knot_ai_consent_v4', message: ask, healthContext: '', history: [], isWebQuery: false, sharedConversation: false, timezone: 'UTC', foregroundTurnVersion: 'knot_foreground_turn_v1', workProgressVersion: 'knot_work_progress_v1', documentProgramVersion: 'knot_document_program_v3', taskExperienceVersion: 'knot_task_experience_v1', clarificationVersion: 'knot_clarification_v1' };
  save('submission.json', submission); admitted = true;
  const receipt = await api('/knot/turns', submission); fact(receipt.task?.id === taskID, 'admission_identity_mismatch');
  let after = 0, terminal = false;
  while (Date.now() - startedAt < 960000) {
    const page = await api('/knot/turns/' + taskID + '?after=' + after);
    fact(page.task?.id === taskID && page.task.conversationID === conversationID && page.task.sourceMessageID === taskID && page.next >= after, 'poll_identity_mismatch');
    appendFileSync(join(privateRoot, 'pages.jsonl'), JSON.stringify({ observedAt: new Date().toISOString(), ...page }) + '\n', { mode: 0o600 });
    for (const frame of page.events) fact(frame.requestID === taskID && frame.sequence === ++after, 'frame_identity_mismatch');
    fact(after === page.next, 'cursor_mismatch');
    if (page.terminal && !page.hasMore) { outcome.terminal = page; terminal = true; break; }
    if (!page.hasMore) await new Promise(resolve => setTimeout(resolve, 1200));
  }
  fact(terminal, 'owned_deadline_without_terminal');
  const events = await api('/knot/shell/events', { bot: 'main', conversationID }); save('events.json', events);
  outcome.failureDiagnostics = (events.records ?? []).flatMap((c: Data) => (c.result?.stdout ?? '').split('\n').filter((s: string) => s.startsWith('KNOT_RESIDENT_FAILURE_V1 ')).map((s: string) => JSON.parse(s.slice('KNOT_RESIDENT_FAILURE_V1 '.length))));
  outcome.failures = events.activities?.filter((a: Data) => /rejected|unavailable/.test(a.kind));
  const docs = (events.documents ?? []).filter((d: Data) => d.sourceMessageID === taskID);
  fact(docs.length === 1 && docs[0].format === spec.format, 'original_format_capture_missing');
  const doc = docs[0], response = await request('/knot/shell/documents', { bot: 'main', conversationID, documentID: doc.id, action: 'file' });
  const bytes = new Uint8Array(await response.arrayBuffer());
  fact(digest(bytes) === doc.sha256 && bytes.length === doc.size && response.headers.get('X-Knot-SHA256') === doc.sha256, 'captured_byte_mismatch');
  const original = new URL('../deliveries/' + name + '-original.' + spec.format, import.meta.url).pathname;
  fact(!existsSync(original), 'delivery_collision'); writeFileSync(original, bytes, { flag: 'wx' });
  outcome.document = { ...doc, originalPath: original, downloadedSHA256: digest(bytes) };
  const inspectionRoot = join(privateRoot, 'independent');
  const inspected = spawnSync('python3', [new URL('./inspect-knot-format-matrix-20261116.py', import.meta.url).pathname, original, inspectionRoot, spec.format], { encoding: 'utf8', env: { ...process.env, PYTHONPATH: join(tmpdir(), 'knot-pdf-inspection-20261116') } });
  if (existsSync(join(inspectionRoot, 'inspection.json'))) outcome.independentInspection = JSON.parse(readFileSync(join(inspectionRoot, 'inspection.json'), 'utf8'));
  fact(inspected.status === 0 && outcome.independentInspection?.sha256 === doc.sha256, 'independent_format_or_content_unconfirmed');
  const history = await api('/knot/conversations/' + conversationID); save('history.json', history);
  fact(Array.isArray(history.messages) && history.messages.some((m: Data) => m.id === taskID && m.text === ask), 'source_history_unconfirmed');
  fact(outcome.terminal.result?.reply === '' && !history.messages.some((m: Data) => m.id === outcome.terminal.task.replyID), 'silent_completion_unconfirmed');
  const retained = await api('/knot/shell/events', { bot: 'main', conversationID });
  fact(retained.documents?.some((d: Data) => d.id === doc.id && d.sha256 === doc.sha256 && d.sourceMessageID === taskID), 'durable_capture_unconfirmed');
  fact(outcome.terminal.task.state === 'completed', 'degraded_terminal_not_acceptance');
  outcome.automatedChecksPassed = true;
  outcome.runtimeScope = 'authenticated_backend_delivery_and_downloaded_bytes_not_phone_or_browser';
  outcome.awaitingVisualReview = ['pdf', 'docx', 'xlsx', 'pptx', 'html'].includes(spec.format);
  outcome.passed = !outcome.awaitingVisualReview;
} catch (error) {
  outcome.issue = error instanceof Error && /^[a-z0-9_]+$/.test(error.message) ? error.message : 'unconfirmed_failure';
  if (admitted) { try { outcome.stopAcknowledgment = await api('/knot/turns/' + taskID + '/cancel', {}); } catch { outcome.stopAcknowledgment = 'unconfirmed'; } }
  process.exitCode = 2;
} finally {
  outcome.endedAt = new Date().toISOString(); outcome.elapsedMs = Date.now() - startedAt;
  save('outcome.json', outcome); writeFileSync(outcomePath, JSON.stringify(outcome, null, 2) + '\n', { flag: 'wx' });
  console.log(JSON.stringify({ scope: name, taskID, caseName, automatedChecksPassed: outcome.automatedChecksPassed ?? false, passed: outcome.passed, issue: outcome.issue, terminalState: outcome.terminal?.task?.state, failureDiagnostics: outcome.failureDiagnostics, outcomePath }));
}
