// Closed-app acceptance for server-owned Knot turns, using only the dedicated
// QA identity created by knot-native-ui-acceptance-account.ts (never a personal
// account). Submits one turn exactly as the native client does, then makes NO
// requests while the "app is closed", and finally reopens to read the result.
// Usage: bun scripts/test-knot-closed-app-turn.ts [closedSeconds]
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { randomUUID } from 'node:crypto';

const backend = 'https://newest-whisper-with-knot-clone-t6ui3ur-backend.rork.app';
const qaAccount = 'ae19aba1-0055-448c-9c70-1e61036908a3';
const closedSeconds = Number(process.argv[2] ?? 90);
const session = JSON.parse(readFileSync(join(tmpdir(), 'knot-native-ui-mayokn2749ag072e3uvbh-20261114', 'api-session.json'), 'utf8'));
if (session.accountID !== qaAccount) throw new Error('dedicated_qa_identity_required');
const headers = { 'X-Whisper-Authorization': 'Bearer ' + session.accessToken, 'Content-Type': 'application/json' };
const log = (step: string, data: unknown = {}) => console.log(JSON.stringify({ at: new Date().toISOString(), step, ...data as object }));
const replyID = (id: string) => (parseInt(id[0], 16) ^ 8).toString(16) + id.slice(1);

async function call(path: string, init: RequestInit = {}) {
  const response = await fetch(backend + path, { ...init, headers, redirect: 'error' });
  const text = await response.text();
  let body: any; try { body = JSON.parse(text); } catch { body = text.slice(0, 300); }
  return { status: response.status, body };
}

const index = await call('/knot/turns');
if (index.status !== 200) throw new Error('index_http_' + index.status);
const source = randomUUID(), conversation = randomUUID();
const message = 'What is the sum of all prime numbers below 1000? Give the exact number.';
const body = {
  requestID: source, consentVersion: 'knot_ai_consent_v4', message, bot: 'main',
  healthContext: `CURRENT DEVICE DATE: ${new Date().toISOString()}; TIME ZONE: UTC.`, history: [],
  isWebQuery: false, sharedConversation: false, timezone: 'UTC',
  conversationID: conversation, sourceMessageID: source, sourceCreatedAt: Date.now(),
  taskModelConsentVersion: 'knot_task_models_v1', taskExperienceVersion: 'knot_task_experience_v1',
  foregroundTurnVersion: 'knot_foreground_turn_v1', workProgressVersion: 'knot_work_progress_v1',
  backgroundApprovalEpoch: index.body.approvalEpoch,
};
const submitted = await call('/knot/turns', { method: 'POST', body: JSON.stringify(body) });
log('submitted', { status: submitted.status, task: submitted.body?.task?.id, state: submitted.body?.task?.state, error: submitted.body?.error });
if (submitted.status !== 202 && submitted.status !== 200) process.exit(2);

// App closed: zero requests, no open stream, no polling.
log('app_closed', { seconds: closedSeconds });
await Bun.sleep(closedSeconds * 1000);

const reopened = await call(`/knot/turns/${source}?after=0`);
const types = (reopened.body?.events ?? []).map((e: any) => e.type);
log('reopened', { status: reopened.status, state: reopened.body?.task?.state, terminal: reopened.body?.terminal, events: types.length, eventTypes: [...new Set(types)], reply: reopened.body?.result?.reply });
const chat = await call(`/knot/conversations/${conversation}`);
const messages = (chat.body?.messages ?? []) as any[];
const delivered = messages.find(m => m.id === replyID(source));
log('history', { status: chat.status, messages: messages.length, userSaved: messages.some(m => m.id === source), replyDelivered: !!delivered, replyText: delivered?.text });
const pass = reopened.body?.terminal === true && reopened.body?.task?.state === 'completed' && !!delivered && /76[,\s]?127/.test(delivered.text ?? '');
log(pass ? 'PASS' : 'NOT_PASSED', { task: source });
process.exit(pass ? 0 : 1);
