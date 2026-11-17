// Explicit owner-authorized November 14 OSRS diagnosis / one fresh game scope.
// Exact existing owner and current clone only. Never consume account.json or a
// user-supplied password. Tokens and raw private evidence remain outside Git.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash } from 'node:crypto';
export type Data = Record<string, any>;
export const backend = 'https://newest-whisper-with-knot-clone-t6ui3ur-backend.rork.app';
export const projectRef = 'uryyyegnbtlmyhqlgndy';
export const accountID = '71b598c5-b235-46e4-90ba-9ae0e4ee9280';
export const workspaceID = 'whisper-' + accountID;
const supabase = 'https://' + projectRef + '.supabase.co';
export const directory = join(tmpdir(), 'knot-owner-osrs-mayokn2749ag072e3uvbh-20261114');
const sessionPath = join(directory, 'owner-session.json');
export const hash = (data: string | Uint8Array) => createHash('sha256').update(data).digest('hex');
export function fact(value: unknown, code: string): asserts value { if (!value) throw new Error(code); }
export const emit = (data: unknown) => console.log(JSON.stringify(data));
export const safeReason = (error: unknown) => error instanceof Error && /^[a-z0-9_]{1,120}$/.test(error.message) ? error.message : 'transport_or_evidence_unconfirmed';
export function save(name: string, value: unknown, exclusive = false) {
  fact(/^[a-zA-Z0-9_.-]+$/.test(name), 'private_filename_required');
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  writeFileSync(join(directory, name), JSON.stringify(value, null, 2) + '\n', { mode: 0o600, flag: exclusive ? 'wx' : 'w' });
}
async function auth(path: string, key: string, body?: unknown, bearer = key): Promise<Data> {
  const response = await fetch(supabase + path, { method: body === undefined ? 'GET' : 'POST', redirect: 'error', headers: { apikey: key, Authorization: 'Bearer ' + bearer, 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(20000) });
  fact(response.ok, 'owner_auth_http_' + response.status);
  return await response.json() as Data;
}
export async function prepareSession() {
  fact(!existsSync(sessionPath) && !existsSync(join(directory, 'session-issuance-intent.json')), 'owner_session_issuance_already_attempted');
  const key = process.env.KNOT_ACCEPTANCE_SUPABASE_SERVICE_ROLE_KEY;
  fact(key, 'authorized_admin_credential_unavailable');
  const user = await auth('/auth/v1/admin/users/' + accountID, key);
  // Exact ID was independently resolved by read-only exact-email lookup.
  fact(user.id === accountID && typeof user.email === 'string' && user.email.includes('@') && user.user_metadata?.dedicated_knot_acceptance !== true, 'exact_existing_owner_required');
  save('session-issuance-intent.json', { accountID, workspaceID, projectRef, backend, startedAt: new Date().toISOString(), scope: 'owner_authorized_osrs_pdf_diagnosis_and_one_fresh_game', method: 'admin_magiclink_verify_no_send', createsAccount: false, changesPassword: false, sendsEmail: false }, true);
  const generated = await auth('/auth/v1/admin/generate_link', key, { type: 'magiclink', email: user.email });
  fact(generated.id === accountID && typeof generated.hashed_token === 'string' && generated.hashed_token, 'owner_link_identity_mismatch');
  const session = await auth('/auth/v1/verify', key, { type: 'email', token_hash: generated.hashed_token });
  fact(session.user?.id === accountID && typeof session.access_token === 'string', 'owner_session_identity_mismatch');
  const claims = JSON.parse(Buffer.from(session.access_token.split('.')[1], 'base64url').toString());
  fact(claims.sub === accountID && claims.iss === supabase + '/auth/v1' && claims.exp * 1000 > Date.now() + 300000, 'owner_session_claims_mismatch');
  const confirmed = await auth('/auth/v1/user', key, undefined, session.access_token);
  fact(confirmed.id === accountID, 'owner_authority_mismatch');
  save('owner-session.json', { accountID, workspaceID, projectRef, accessToken: session.access_token, issuedAt: new Date().toISOString() }, true);
  emit({ status: 'exact_owner_session_verified', accountID, projectRef, noAccountCreation: true, noPasswordChange: true, noEmailSent: true, credentialsPrinted: false });
}
function token(): string {
  const saved = JSON.parse(readFileSync(sessionPath, 'utf8')) as Data;
  const claims = JSON.parse(Buffer.from(saved.accessToken.split('.')[1], 'base64url').toString());
  fact(saved.accountID === accountID && saved.workspaceID === workspaceID && saved.projectRef === projectRef && claims.sub === accountID && claims.iss === supabase + '/auth/v1' && claims.exp * 1000 > Date.now() + 30000, 'exact_owner_live_session_required');
  return saved.accessToken;
}
export async function managed(path: string, body?: unknown, maximumMs = 25000, signal?: AbortSignal, expectedBuild?: string): Promise<Response> {
  fact(path.startsWith('/knot/') || path === '/health', 'current_knot_route_required');
  const response = await fetch(backend + path, { method: body === undefined ? 'GET' : 'POST', redirect: 'error', headers: { 'X-Whisper-Authorization': 'Bearer ' + token(), 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.any([AbortSignal.timeout(maximumMs), ...(signal ? [signal] : [])]) });
  if (expectedBuild) {
    const worker = response.headers.get('X-Knot-Worker-Build'), actor = response.headers.get('X-Knot-Actor-Build');
    fact(worker === expectedBuild && (!actor || actor === expectedBuild), 'serving_build_mismatch_no_replay');
  }
  return response;
}
export async function checked(path: string, body?: unknown, expectedBuild?: string): Promise<Data> {
  const response = await managed(path, body, 25000, undefined, expectedBuild);
  fact(response.ok, 'managed_http_' + response.status);
  return await response.json() as Data;
}
export async function discover() {
  const chats: Data[] = []; let after: string | null = null;
  do {
    const page = await checked('/knot/conversations' + (after ? '?after=' + encodeURIComponent(after) : ''));
    fact(Array.isArray(page.conversations), 'owned_conversation_page_required');
    chats.push(...page.conversations); after = page.next;
    fact(chats.length <= 1000, 'conversation_page_limit');
  } while (after);
  save('conversation-index.json', chats);
  const candidates = chats.filter(chat => !chat.deleted && /osrs|fractures|archive|rpg|game/i.test(String(chat.title)));
  save('candidate-conversations.json', candidates);
  emit({ status: 'owned_history_index_read_only', conversations: chats.length, ownedConversationIDs: chats.filter(c => !c.deleted).map(c => ({ id: c.id, botID: c.botID })), candidates: candidates.map(({ id, botID, title, updatedAt }) => ({ id, botID, title, updatedAt })), mutations: 0, historicalReplay: false });
}
export async function inspect(conversationID: string) {
  fact(/^[a-f0-9-]{36}$/.test(conversationID), 'exact_conversation_required');
  const index = JSON.parse(readFileSync(join(directory, 'conversation-index.json'), 'utf8')) as Data[];
  const chat = index.find(c => c.id === conversationID && !c.deleted);
  fact(chat && chat.botID === 'main', 'owned_main_conversation_required');
  const messages: Data[] = []; let next: Data | null = null;
  do {
    const page = await checked('/knot/conversations/' + conversationID + (next ? '?after=' + next.after + '&afterID=' + next.afterID : ''));
    fact(Array.isArray(page.messages), 'owned_messages_required'); messages.push(...page.messages); next = page.next;
    fact(messages.length <= 2000, 'message_page_limit');
  } while (next);
  save(conversationID + '-messages.json', messages);
  const events = await checked('/knot/shell/events', { bot: 'main', conversationID });
  save(conversationID + '-events.json', events);
  const targetTasks = new Set(['ff1ec610-bba1-48f4-8bbb-73485b63436e', 'e9e11652-e0d9-4881-84da-3d0f1006bc9d']);
  const records = (events.records ?? []).filter((row: Data) => targetTasks.has(row.taskID));
  const details: Data[] = [];
  for (const row of records) {
    const proposalID = row.spec.id;
    const detail = await checked('/knot/shell/events', { bot: 'main', conversationID, proposalID });
    save(proposalID + '-events.json', detail);
    const retained = await checked('/knot/shell/status', { bot: 'main', conversationID, proposalID, persistedOnly: true });
    save(proposalID + '-status.json', retained);
    const manifestLine = String(retained.stdout ?? '').split('\n').find(line => line.startsWith('KNOT_DOCUMENT_V1 '));
    let manifest: Data | undefined;
    if (manifestLine) { try { manifest = JSON.parse(manifestLine.slice('KNOT_DOCUMENT_V1 '.length)); } catch { /* Retain original privately. */ } }
    details.push({ proposalID, taskID: row.taskID, stage: row.spec.documentInvocation?.stage, status: row.result?.status, exitCode: row.result?.exitCode, sourcePath: row.spec.documentInvocation?.path, manifest: manifest ? { path: manifest.path, title: manifest.title, format: manifest.format, sha256: manifest.sha256, size: manifest.size, pages: manifest.pages, proofCount: manifest.proofs?.length, verification: manifest.verification } : undefined, events: (detail.events ?? []).filter((event: Data) => /content|document_proof|capture|source|qualified/.test(event.kind)) });
  }
  const summary = { title: 'Read-only historical OSRS task evidence', observedAt: new Date().toISOString(), accountID, backend, conversationID, messageCount: messages.length, targetTaskIDs: [...new Set(records.map((row: Data) => row.taskID))], relevantUserAsks: messages.filter(m => m.role === 'user' && /osrs|fractures/i.test(m.text)).map(m => ({ id: m.id, text: m.text, createdAt: m.createdAt })), targetActivities: (events.activities ?? []).filter((a: Data) => targetTasks.has(a.taskID)), records: details, capturedDocuments: (events.documents ?? []).filter((d: Data) => records.some((r: Data) => r.spec.id === d.proposalID)).map((d: Data) => ({ id: d.id, title: d.title, format: d.format, sha256: d.sha256 })), historicalReplay: false, commandsExecuted: 0 };
  save(conversationID + '-diagnosis.json', summary);
  emit({ ...summary, targetActivities: summary.targetActivities.filter((a: Data) => ['document_work_unavailable', 'tool_selection_unavailable', 'document_content_unavailable'].includes(a.kind)) });
}
if (process.argv[1]?.endsWith('/knot-owner-osrs-access.ts')) {
  (async () => {
    if (process.argv.includes('--prepare-session')) return prepareSession();
    if (process.argv.includes('--discover')) return discover();
    if (process.argv.includes('--inspect')) return inspect(process.argv[process.argv.indexOf('--inspect') + 1]);
    throw new Error('explicit_read_or_session_mode_required');
  })().catch(error => { emit({ status: 'blocked', reason: safeReason(error) }); process.exitCode = 2; });
}
