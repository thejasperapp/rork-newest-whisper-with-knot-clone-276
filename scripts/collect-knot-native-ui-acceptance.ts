// Read-only receipts from the exact newly authorized native QA identity only.
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
const accountID = 'bad7b131-6b05-44c8-a450-a30f4748639f';
const projectRef = 'uryyyegnbtlmyhqlgndy';
const backend = 'https://newest-whisper-with-knot-clone-t6ui3ur-backend.rork.app';
const build = '178f79bcc6b19776fe27a0aa4bf24dc1a5bfd3e411e7590c798e650ad04dfe97';
const label = process.argv[2];
if (!/^20261114-[a-z][a-z0-9-]{0,60}$/.test(label ?? '')) throw new Error('unique_observation_label_required');
function fact(value: unknown, reason: string): asserts value { if (!value) throw new Error(reason); }
async function main() {
  const state = JSON.parse(readFileSync(join(tmpdir(), 'knot-native-ui-mayokn2749ag072e3uvbh-20261114', 'api-session.json'), 'utf8'));
  const claims = JSON.parse(Buffer.from(state.accessToken.split('.')[1], 'base64url').toString());
  fact(state.accountID === accountID && state.projectRef === projectRef && claims.sub === accountID && claims.iss === `https://${projectRef}.supabase.co/auth/v1` && claims.exp * 1000 > Date.now(), 'exact_new_native_qa_session_required');
  async function get(path: string, body?: unknown): Promise<any> {
    const response = await fetch(backend + path, { redirect: 'error', method: body ? 'POST' : 'GET', headers: { 'X-Whisper-Authorization': 'Bearer ' + state.accessToken, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(25000) });
    fact(response.ok, 'native_evidence_read_' + (path.startsWith('/knot/documents') ? 'documents' : path.includes('/shell/') ? 'events' : path === '/knot/conversations' ? 'index' : 'messages') + '_http_' + response.status);
    const observedBuild = response.headers.get('X-Knot-Worker-Build');
    fact(!observedBuild || observedBuild === build, 'native_evidence_build_mismatch');
    return response.json();
  }
  const index = await get('/knot/conversations');
  fact(index.conversations.length <= 5 && !index.next, 'unexpected_new_qa_conversation_count');
  const chats = [];
  for (const chat of index.conversations) {
    fact(/^[a-f0-9-]{36}$/.test(chat.id) && !chat.deleted, 'invalid_new_qa_conversation');
    const messages = await get('/knot/conversations/' + chat.id);
    const events = await get('/knot/shell/events', { bot: chat.botID, conversationID: chat.id });
    const documents = await get('/knot/shell/documents', { bot: chat.botID, conversationID: chat.id, action: 'list' });
    chats.push({ conversation: chat, messages, events, documents });
  }
  const receipt = { observedAt: new Date().toISOString(), accountID, workspaceID: 'whisper-' + accountID, backend, expectedBuild: build, readOnly: true, chats };
  writeFileSync(new URL('../deliveries/native-knot-ui-' + label + '-observation.json', import.meta.url), JSON.stringify(receipt, null, 2) + '\n', { flag: 'wx' });
  console.log(JSON.stringify({ observedAt: receipt.observedAt, accountID, backend, chats: chats.map(chat => ({ conversationID: chat.conversation.id, messages: chat.messages.messages.map((message: any) => ({ id: message.id, role: message.role, text: message.text, shellID: message.shell?.spec?.id })), records: chat.events.records.map((record: any) => ({ id: record.spec?.id, operation: record.spec?.operation, taskID: record.taskID, status: record.result?.status, exitCode: record.result?.exitCode, workspaceID: record.result?.providerReceipt?.user_id, command: record.spec?.operation === 'work' ? record.spec?.command : undefined, stdout: record.spec?.operation === 'work' ? record.result?.stdout : undefined })), latestActivity: chat.events.activities?.slice(0, 3), documents: chat.documents })) }));
}
main().catch(error => { console.error(JSON.stringify({ status: 'blocked', reason: error instanceof Error && /^[a-z0-9_]+$/.test(error.message) ? error.message : 'native_receipt_read_unavailable' })); process.exitCode = 2; });
