// Explicit owner-authorized file-delivery audit. Auth issuance is an in-memory
// admin magiclink verification (no email/password change). No shell/session
// mutations, replay, capture, workspace rebind, or persisted credentials.
import { createHash } from 'node:crypto';
const owner = '71b598c5-b235-46e4-90ba-9ae0e4ee9280';
const backend = 'https://newest-whisper-with-knot-clone-t6ui3ur-backend.rork.app';
const base = 'https://uryyyegnbtlmyhqlgndy.supabase.co';
const key = process.env.KNOT_ACCEPTANCE_SUPABASE_SERVICE_ROLE_KEY;
if (!key) throw new Error('owner_admin_credential_unavailable');
const sha = (v: string | Uint8Array) => createHash('sha256').update(v).digest('hex');
async function auth(path: string, body?: unknown) {
  const r = await fetch(base + path, { method: body ? 'POST' : 'GET', headers: { apikey: key!, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(20000), redirect: 'error' });
  if (!r.ok) throw new Error('auth_http_' + r.status);
  return r.json() as Promise<Record<string, any>>;
}
const identity = await auth('/auth/v1/admin/users/' + owner);
if (identity.id !== owner || identity.user_metadata?.dedicated_knot_acceptance === true || !identity.email) throw new Error('exact_nonsynthetic_owner_required');
const link = await auth('/auth/v1/admin/generate_link', { type: 'magiclink', email: identity.email });
const session = await auth('/auth/v1/verify', { type: 'email', token_hash: link.hashed_token });
if (session.user?.id !== owner) throw new Error('owner_session_mismatch');
async function api(path: string, body?: unknown) {
  const r = await fetch(backend + path, { method: body ? 'POST' : 'GET', headers: { 'X-Whisper-Authorization': 'Bearer ' + session.access_token, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(30000), redirect: 'error' });
  if (!r.ok) throw new Error('managed_http_' + r.status);
  return r.json() as Promise<Record<string, any>>;
}
console.log(JSON.stringify({ observedAt: new Date().toISOString(), owner, synthetic: false, authSessionCreated: true, credentialsPersisted: false, credentialsPrinted: false }));
const chats = await api('/knot/conversations');
console.log(JSON.stringify({ chats: chats.conversations?.filter((c: any) => !c.deleted && c.botID === 'main').map((c: any) => ({ id: c.id, updatedAt: c.updatedAt })) }));
for (const conversationID of ['549a559d-3f67-40e8-bbce-9ca95e6ddb8d', 'fedcba15-f13a-4bcd-9bbb-6179b3c1a310']) {
  const events = await api('/knot/shell/events', { bot: 'main', conversationID });
  console.log(JSON.stringify({ conversationID, unresolved: events.records?.filter((r: any) => r.state === 'uncertain'), failures: events.activities?.filter((a: any) => /rejected|unavailable/.test(a.kind)), documents: events.documents?.map((d: any) => ({ id: d.id, sha256: d.sha256, format: d.format, sourceMessageID: d.sourceMessageID })) }));
  for (const r of events.records ?? []) if (r.state === 'uncertain') {
    const detail = await api('/knot/shell/events', { bot: 'main', conversationID, proposalID: r.spec.id });
    console.log(JSON.stringify({ conversationID, proposalID: r.spec.id, events: detail.events }));
  }
}
const memory = await api('/knot/shell/memory', { bot: 'main', conversationID: '549a559d-3f67-40e8-bbce-9ca95e6ddb8d', action: 'read' });
console.log(JSON.stringify({ managedOwnerMemory: { exists: memory.exists, bytes: memory.bytes, sha256: typeof memory.text === 'string' ? sha(memory.text) : null } }));
const token = process.env.SIDECAR_TOKEN_WHISPER;
if (token) {
  const r = await fetch('https://knot-shell.mydailywhisper.com/files?path=MEMORY.md&user_id=' + encodeURIComponent('whisper-' + owner), { headers: { Authorization: 'Bearer ' + token }, signal: AbortSignal.timeout(15000), redirect: 'error' });
  const bytes = new Uint8Array(await r.arrayBuffer());
  console.log(JSON.stringify({ ownerNamespaceMemory: { workspace: 'whisper-' + owner, status: r.status, bytes: r.ok ? bytes.length : undefined, sha256: r.ok ? sha(bytes) : undefined, matchesManaged: r.ok && typeof memory.text === 'string' && sha(bytes) === sha(memory.text) } }));
}
