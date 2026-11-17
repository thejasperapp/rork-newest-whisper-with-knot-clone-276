import { dispatchKnotActor, knotWorkspaceID, type KnotShellEnv } from './knot-shell';
import { knotBots, type KnotBot } from './knot-agent';
import { artifactImportCommand, type ArtifactImportResource as Resource } from './knot-artifact-import';
import { cleanKnotDocuments, ownedKnotDocument, readKnotDocument, reserveKnotDocumentBytes, storeKnotDocumentResource, knotStoredResource, verifiedKnotWorkspaceFile, type KnotDocument } from './knot-documents';
import { discoverKnotShell, endpoint, readSidecarBytes, readSidecarText, sidecarRequest, SidecarHTTPError } from './knot-shell-discovery';

const prefix = '::whisper-artifact-v1::';
const database = 'https://uryyyegnbtlmyhqlgndy.supabase.co/rest/v1';
const uuid = (v: unknown): v is string => typeof v === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(v);
const digest = (v: unknown): v is string => typeof v === 'string' && /^[a-f0-9]{64}$/.test(v);
const json = (v: unknown, status = 200) => Response.json(v, { status, headers: { 'Cache-Control': 'no-store' } });
const sha = async (v: Uint8Array) => [...new Uint8Array(await crypto.subtle.digest('SHA-256', v))].map(b => b.toString(16).padStart(2, '0')).join('');
const hashText = (v: string) => sha(new TextEncoder().encode(v));
type ShareEnv = KnotShellEnv & { EXPO_PUBLIC_SUPABASE_ANON_KEY?: string };
type Source = { owner: string; bot: KnotBot; conversationID: string; documentID: string };
type Grant = { messageID: string; recipientID: string; source: Source; document: KnotDocument };
type Message = { id: string; from_user_id: string; to_user_id: string; from_username: string; body: string; thread_id: string; created_at: string };
type Import = { messageID: string; document: KnotDocument; source: Source; workspace: string; copied: number; resource: number; offset: number; sequence: number; job?: { id?: string; sequence: number }; done?: boolean };
const flights = new WeakMap<DurableObjectState, Set<string>>();
async function parse(response: Pick<Response, 'body'>, limit = 150000): Promise<any> { return JSON.parse(await readSidecarText(response, limit)); }
function publicDocument(original: KnotDocument): KnotDocument {
  // Source paths, private source text and review reference material never leave
  // the owner's actor. Keep identity and non-private quality outcomes only.
  const { sourcePath: _path, sourceMessageID: _message, contentReview: _content, verification: _proof, visualReview: _visual, visualAdvisory: _advisory, reviewIssue: _reviewIssue, qualityShortfalls: _shortfalls, ...safe } = original;
  return { ...safe, proofPages: [], review: original.review === 'issues' ? 'issues' : 'not_requested', ...(original.qualityShortfalls?.length ? { qualityShortfalls: ['The original delivery recorded quality shortfalls.'] } : {}) };
}
function resources(document: KnotDocument): Resource[] {
  return [{ resource: 0, size: document.size, sha256: document.sha256, path: document.name }, ...(document.bundle?.assets.map(a => ({ resource: a.resourceID, size: a.size, sha256: a.sha256, path: a.path })) ?? [])];
}
function same(a: KnotDocument, b: KnotDocument): boolean {
  return a.id === b.id && a.name === b.name && a.sha256 === b.sha256 && a.size === b.size && a.format === b.format && a.contentType === b.contentType && a.proposalID === b.proposalID && JSON.stringify(a.bundle) === JSON.stringify(b.bundle);
}
function state(ctx: DurableObjectState, id: string): Import | undefined {
  const row = ctx.storage.sql.exec<{ data: string }>('SELECT data FROM knot_document_share_imports WHERE message_id=?', id).toArray()[0];
  return row ? JSON.parse(row.data) as Import : undefined;
}
function live(ctx: DurableObjectState, value: Import, signal: AbortSignal): void {
  signal.throwIfAborted();
  if (!state(ctx, value.messageID) || !ctx.storage.sql.exec('SELECT 1 FROM knot_documents WHERE id=?', value.document.id).toArray().length || ctx.storage.sql.exec("SELECT 1 FROM knot_document_deletions WHERE conversation_id IN (?, '*')", value.messageID).toArray().length) throw new Error('document_removed');
}
function save(ctx: DurableObjectState, value: Import): void { ctx.storage.sql.exec('UPDATE knot_document_share_imports SET data=? WHERE message_id=?', JSON.stringify(value), value.messageID); }
function progress(value: Import) {
  const all = resources(value.document), total = all.reduce((n, r) => n + r.size, 0);
  const written = all.slice(0, value.resource).reduce((n, r) => n + r.size, 0) + value.offset;
  return { done: value.done === true, progress: value.done ? 1 : Math.min(0.99, (value.copied === all.length ? total + written : all.slice(0, value.copied).reduce((n, r) => n + r.size, 0)) / (total * 2)), ...(value.done ? { document: value.document, path: value.document.sourcePath } : {}) };
}

/** All message reads and contact checks use the member's JWT, not service-role
 * message visibility. A pointer or a guessed UUID alone grants nothing. */
async function social(request: Request, env: ShareEnv, path: string, method = 'GET', body?: unknown): Promise<any> {
  if (!env.EXPO_PUBLIC_SUPABASE_ANON_KEY) throw new Error('sharing_unavailable');
  const response = await fetch(database + path, { method, redirect: 'manual', headers: {
    apikey: env.EXPO_PUBLIC_SUPABASE_ANON_KEY, Authorization: request.headers.get('Authorization') ?? '', 'Content-Type': 'application/json',
  }, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.any([request.signal, AbortSignal.timeout(6000)]) });
  if (!response.ok) { await response.body?.cancel(); throw new Error('sharing_access_denied'); }
  return parse(response, 20000);
}
async function contact(request: Request, env: ShareEnv, sender: string, recipient: string): Promise<void> {
  if (!uuid(sender) || !uuid(recipient) || sender === recipient || await social(request, env, '/rpc/whisper_can_contact', 'POST', { p_sender: sender, p_recipient: recipient }) !== true) throw new Error('sharing_access_denied');
}
async function message(request: Request, env: ShareEnv, owner: string, id: unknown): Promise<Message> {
  if (!uuid(id)) throw new Error('invalid_share');
  const rows = await social(request, env, '/whisper_messages?id=eq.' + id + '&select=id,from_user_id,to_user_id,from_username,body,thread_id,created_at&limit=1');
  const row = Array.isArray(rows) && rows.length === 1 ? rows[0] as Message : undefined;
  const hex = row ? (await hashText([row.from_user_id, row.to_user_id].sort().join('|'))).slice(0, 32) : '';
  const threadID = [hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16), hex.slice(16, 20), hex.slice(20)].join('-');
  if (!row || row.id !== id || ![row.from_user_id, row.to_user_id].includes(owner) || row.body.split('\n')[0] !== prefix + id ||
      !uuid(row.from_user_id) || !uuid(row.to_user_id) || row.thread_id !== threadID || !Number.isFinite(Date.parse(row.created_at))) throw new Error('sharing_access_denied');
  await contact(request, env, row.from_user_id, row.to_user_id);
  return row;
}
async function senderName(request: Request, env: ShareEnv, sender: string): Promise<string> {
  // Attribution is derived from the account-bound profile, not the username
  // field that a message client could have supplied at insertion time.
  const rows = await social(request, env, '/whisper_profiles?user_id=eq.' + sender + '&select=user_id,username&limit=1');
  const row = Array.isArray(rows) ? rows[0] : undefined;
  return row?.user_id === sender && typeof row.username === 'string' && row.username.trim() ? '@' + row.username.replace(/[\x00-\x1f\x7f]/g, '').trim().slice(0, 119) : 'A Whisper member';
}
async function grant(env: KnotShellEnv, row: Message, signal: AbortSignal): Promise<Grant> {
  const response = await dispatchKnotActor(env, row.from_user_id, 'artifact-share/grant', { messageID: row.id, recipientID: row.to_user_id }, signal);
  if (!response.ok) { await response.body?.cancel(); throw new Error('document_removed'); }
  const value = await parse(response) as Grant;
  if (value.messageID !== row.id || value.recipientID !== row.to_user_id) throw new Error('invalid_share');
  return value;
}
export async function knotArtifactSharingRoute(request: Request, env: ShareEnv, owner: string): Promise<Response> {
  if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  try {
    const action = new URL(request.url).pathname.split('/').pop();
    const body = await parse(request, 12000) as Record<string, unknown>;
    if (action === 'prepare') {
      if (!uuid(body.messageID) || !uuid(body.recipientID)) return json({ error: 'invalid_share' }, 400);
      await contact(request, env, owner, body.recipientID);
      let source: Source;
      if (body.sourceMessageID !== undefined) {
        const row = await message(request, env, owner, body.sourceMessageID);
        const saved = await dispatchKnotActor(env, owner, 'artifact-share/saved', { messageID: row.id }, request.signal);
        const own = await parse(saved) as { document?: KnotDocument };
        source = own.document ? { owner, bot: 'main', conversationID: row.id, documentID: own.document.id } : (await grant(env, row, request.signal)).source;
      } else {
        if (!uuid(body.conversationID) || !digest(body.documentID) || !knotBots.includes(body.bot as KnotBot)) return json({ error: 'invalid_share' }, 400);
        source = { owner, bot: body.bot as KnotBot, conversationID: body.conversationID, documentID: body.documentID };
      }
      const response = await dispatchKnotActor(env, source.owner, 'artifact-share/original', source, request.signal);
      if (!response.ok) return response;
      const original = await parse(response) as KnotDocument;
      return dispatchKnotActor(env, owner, 'artifact-share/prepare', { messageID: body.messageID, recipientID: body.recipientID, source, document: publicDocument(original) }, request.signal);
    }
    const row = await message(request, env, owner, body.messageID);
    if (action === 'resolve' || action === 'resource') {
      const savedResponse = await dispatchKnotActor(env, owner, 'artifact-share/saved', { messageID: row.id }, request.signal);
      const saved = await parse(savedResponse) as { document?: KnotDocument };
      const shared = saved.document ? undefined : await grant(env, row, request.signal);
      const document = saved.document ?? shared!.document;
      if (action === 'resolve') return json({ document, senderName: await senderName(request, env, row.from_user_id), sentAt: row.created_at, saved: !!saved.document });
      if (!['file', 'asset'].includes(String(body.action))) return json({ error: 'invalid_document_resource' }, 400);
      const source = saved.document ? { owner, bot: 'main' as const, conversationID: row.id, documentID: document.id } : shared!.source;
      return dispatchKnotActor(env, source.owner, 'artifact-share/resource', { ...source, document, action: body.action, resourceID: body.resourceID }, request.signal);
    }
    if (action === 'save') {
      if (owner !== row.to_user_id || body.confirm !== true) return json({ error: 'sharing_access_denied' }, 403);
      // Resume recipient-owned work without requiring the sender's file again.
      const existing = await dispatchKnotActor(env, owner, 'artifact-share/save-status', { messageID: row.id }, request.signal);
      const status = await parse(existing) as { exists?: boolean };
      const shared = status.exists ? undefined : await grant(env, row, request.signal);
      const workspace = await knotWorkspaceID(env, owner, 'main', row.id, request.signal);
      return dispatchKnotActor(env, owner, 'artifact-share/save', { messageID: row.id, workspace, ...(shared ? { shared, senderName: await senderName(request, env, row.from_user_id), sentAt: row.created_at, senderID: row.from_user_id } : {}) }, request.signal);
    }
    return json({ error: 'not_found' }, 404);
  } catch (error) {
    const reason = error instanceof Error ? error.message : '';
    return json({ error: ['sharing_access_denied', 'document_removed', 'invalid_share'].includes(reason) ? reason : 'sharing_unavailable' }, reason === 'sharing_access_denied' ? 403 : reason === 'document_removed' ? 410 : 503);
  }
}

export function initializeKnotArtifactSharing(ctx: DurableObjectState): void {
  ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS knot_document_shares (message_id TEXT PRIMARY KEY, data TEXT NOT NULL)');
  ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS knot_document_share_imports (message_id TEXT PRIMARY KEY, data TEXT NOT NULL)');
}
export function eraseKnotArtifactShares(ctx: DurableObjectState, conversationID?: string): void {
  if (!conversationID) { ctx.storage.sql.exec('DELETE FROM knot_document_shares'); ctx.storage.sql.exec('DELETE FROM knot_document_share_imports'); return; }
  ctx.storage.sql.exec("DELETE FROM knot_document_shares WHERE json_extract(data,'$.source.conversationID')=?", conversationID);
  ctx.storage.sql.exec('DELETE FROM knot_document_share_imports WHERE message_id=?', conversationID);
}

/** Internal account-actor routes only. The public route never accepts a source
 * owner, workspace, saved metadata, command, job ID, or resource path. */
export async function knotArtifactSharingActor(ctx: DurableObjectState, env: KnotShellEnv, path: string, body: Record<string, any>, signal: AbortSignal): Promise<Response> {
  initializeKnotArtifactSharing(ctx);
  try {
    if (path === '/artifact-share/original' || path === '/artifact-share/resource') {
      const doc = ownedKnotDocument(ctx, String(body.bot), String(body.conversationID), String(body.documentID));
      if (!doc) return json({ error: 'document_removed' }, 410);
      if (path.endsWith('/original')) return json(publicDocument(doc));
      if (!same(doc, body.document as KnotDocument)) return json({ error: 'document_identity_changed' }, 409);
      return readKnotDocument(ctx, env, body.bot, body.conversationID, { action: body.action, resourceID: body.resourceID, documentID: doc.id }, signal);
    }
    if (!uuid(body.messageID)) return json({ error: 'invalid_share' }, 400);
    if (path === '/artifact-share/prepare') {
      if (ctx.storage.sql.exec("SELECT 1 FROM knot_document_deletions WHERE conversation_id='*'").toArray().length) return json({ error: 'document_removed' }, 410);
      const old = ctx.storage.sql.exec<{ data: string }>('SELECT data FROM knot_document_shares WHERE message_id=?', body.messageID).toArray()[0];
      let value: Grant = { messageID: body.messageID, recipientID: body.recipientID, source: body.source, document: body.document };
      if (old) {
        const previous = JSON.parse(old.data) as Grant;
        if (previous.recipientID !== value.recipientID || JSON.stringify(previous.source) !== JSON.stringify(value.source) || !same(previous.document, value.document)) return json({ error: 'share_identity_conflict' }, 409);
        value = previous; // Retry retains the exact first prepared card/body.
      }
      if (!old && ctx.storage.sql.exec<{ count: number }>('SELECT COUNT(*) AS count FROM knot_document_shares').one().count >= 500) return json({ error: 'document_storage_full' }, 409);
      ctx.storage.sql.exec('INSERT OR IGNORE INTO knot_document_shares VALUES (?,?)', value.messageID, JSON.stringify(value));
      const title = (value.document.title || value.document.name).replace(/[\x00-\x1f\x7f]/g, ' ').slice(0, 120);
      return json({ body: prefix + value.messageID + '\n' + title });
    }
    if (path === '/artifact-share/grant') {
      const row = ctx.storage.sql.exec<{ data: string }>('SELECT data FROM knot_document_shares WHERE message_id=?', body.messageID).toArray()[0];
      const value = row ? JSON.parse(row.data) as Grant : undefined;
      return value?.recipientID === body.recipientID ? json(value) : json({ error: 'document_removed' }, 410);
    }
    const current = state(ctx, body.messageID);
    if (path === '/artifact-share/save-status') return json({ exists: !!current });
    if (path === '/artifact-share/saved') return json({ ...(current?.done ? { document: current.document } : {}) });
    if (path !== '/artifact-share/save') return json({ error: 'not_found' }, 404);
    let locked = flights.get(ctx); if (!locked) { locked = new Set(); flights.set(ctx, locked); }
    if (locked.has(body.messageID)) return json({ error: 'save_in_progress' }, 409);
    locked.add(body.messageID);
    try { return await importStep(ctx, env, body, signal); }
    finally { locked.delete(body.messageID); }
  } catch (error) {
    const reason = error instanceof Error ? error.message : '';
    return json({ error: ['save_uncertain', 'document_removed', 'document_storage_full', 'workspace_file_conflict', 'workspace_save_failed'].includes(reason) ? reason : 'workspace_save_unavailable' }, 409);
  }
}

async function importStep(ctx: DurableObjectState, env: KnotShellEnv, body: Record<string, any>, signal: AbortSignal): Promise<Response> {
  cleanKnotDocuments(ctx);
  let value = state(ctx, body.messageID);
  if (!value) {
    const shared = body.shared as Grant;
    if (!shared || shared.messageID !== body.messageID || !uuid(body.senderID)) throw new Error('invalid_share');
    const id = await hashText('knot-received-artifact-v1:' + shared.recipientID + ':' + body.messageID);
    signal.throwIfAborted();
    if (ctx.storage.sql.exec("SELECT 1 FROM knot_document_deletions WHERE conversation_id IN (?, '*')", body.messageID).toArray().length) throw new Error('document_removed');
    value = state(ctx, body.messageID);
    if (!value) {
      if (ctx.storage.sql.exec<{ count: number }>('SELECT COUNT(*) AS count FROM knot_documents').one().count >= 500) throw new Error('document_storage_full');
      const document: KnotDocument = { ...shared.document, id, proposalID: body.messageID, createdAt: new Date().toISOString(), expiresAt: new Date(Date.now() + 7 * 86400000).toISOString(), sourcePath: 'received/' + body.messageID + '/' + shared.document.name,
        provenance: { senderID: body.senderID, senderName: String(body.senderName).slice(0, 120), sentAt: body.sentAt, savedAt: new Date().toISOString(), messageID: body.messageID, originalDocumentID: shared.document.id } };
      value = { messageID: body.messageID, document, source: shared.source, workspace: body.workspace, copied: 0, resource: 0, offset: 0, sequence: 0 };
      ctx.storage.transactionSync(() => {
        ctx.storage.sql.exec('INSERT INTO knot_document_share_imports VALUES (?,?)', value!.messageID, JSON.stringify(value));
        ctx.storage.sql.exec('INSERT INTO knot_documents VALUES (?,?,?,?,?,?)', id, 'share-pending', body.messageID, Date.now() + 7 * 86400000, 0, JSON.stringify(document));
      });
    }
  }
  live(ctx, value, signal);
  if (value.workspace !== body.workspace) throw new Error('workspace_file_conflict');
  if (value.done) return json(progress(value));
  const all = resources(value.document);
  // Pending bytes share the normal account quota. If seven-day cleanup removed
  // them while paused, reacquire the same original rather than write zeroes or
  // regenerate it. No workspace command is replayed by this cache recovery.
  const missing = all.findIndex((resource, index) => index < value!.copied && ctx.storage.sql.exec<{ size: number }>('SELECT COALESCE(SUM(length(data)),0) AS size FROM knot_document_bytes WHERE id=? AND resource=?', value!.document.id, resource.resource).one().size !== resource.size);
  if (missing >= 0) { value.copied = missing; save(ctx, value); }
  if (value.copied < all.length) {
    const resource = all[value.copied];
    const original = await dispatchKnotActor(env, value.source.owner, 'artifact-share/original', value.source, signal);
    if (!original.ok) throw new Error('document_removed');
    const sourceDocument = await parse(original) as KnotDocument;
    const sourceResources = resources(sourceDocument);
    if (sourceDocument.sha256 !== value.document.sha256 || sourceDocument.name !== value.document.name || JSON.stringify(sourceResources) !== JSON.stringify(all)) throw new Error('document_identity_changed');
    const response = await dispatchKnotActor(env, value.source.owner, 'artifact-share/resource', { ...value.source, document: sourceDocument, action: resource.resource === 0 ? 'file' : 'asset', resourceID: resource.resource }, signal);
    if (!response.ok) { await response.body?.cancel(); throw new Error('document_removed'); }
    const bytes = await readSidecarBytes(response, resource.size);
    if (bytes.length !== resource.size || await sha(bytes) !== resource.sha256) throw new Error('document_identity_changed');
    live(ctx, value, signal);
    ctx.storage.transactionSync(() => {
      const previous = ctx.storage.sql.exec<{ size: number }>('SELECT COALESCE(SUM(length(data)),0) AS size FROM knot_document_bytes WHERE id=? AND resource=?', value!.document.id, resource.resource).one().size;
      reserveKnotDocumentBytes(ctx, Math.max(0, bytes.length - previous), value!.document.id);
      storeKnotDocumentResource(ctx, value!.document.id, resource.resource, bytes);
      ctx.storage.sql.exec('UPDATE knot_documents SET bytes=bytes+?,expires=? WHERE id=?', bytes.length - previous, Date.now() + 7 * 86400000, value!.document.id);
      value!.copied++; save(ctx, value!);
    });
    return json(progress(value));
  }
  // A fixed, data-only importer uses the advertised one-shot job transport.
  // It never attaches to the member's interactive shell or runs artifact code.
  const caps = await discoverKnotShell(env, { state: ctx });
  if (!endpoint(caps, 'exec_once', 'POST', '/exec') || !endpoint(caps, 'job_status', 'GET', '/jobs/:id')) throw new Error('workspace_save_unavailable');
  live(ctx, value, signal);
  if (value.job) {
    if (value.job.id) {
      const receipt = await parse(await sidecarRequest(env, '/jobs/' + encodeURIComponent(value.job.id), 'GET', undefined, 10000, signal), 16000);
      live(ctx, value, signal);
      if (['queued', 'running', 'pending', 'starting'].includes(receipt.status)) return json(progress(value));
      if (receipt.exit_code !== 0 || receipt.output_complete !== true || receipt.output_late_bytes !== 0) throw new Error('workspace_save_failed');
    }
    // A durable intent with a lost response is reconciled from its exact
    // successful filesystem receipt. Missing evidence NEVER replays the job.
    const stamp = 'received/' + value.messageID + '/.whisper-receipt-' + value.job.sequence;
    try {
      const response = await sidecarRequest(env, '/files?path=' + encodeURIComponent(stamp) + '&user_id=' + encodeURIComponent(value.workspace), 'GET', undefined, 10000, signal);
      if (await readSidecarText(response, 1000) !== value.document.id + ':' + value.job.sequence) throw new Error('workspace_save_failed');
    } catch (error) { if (!value.job.id && error instanceof SidecarHTTPError && error.status === 404) throw new Error('save_uncertain'); throw error; }
    live(ctx, value, signal);
    const resource = all[value.resource];
    if (resource) {
      value.offset = Math.min(resource.size, value.offset + 48000);
      if (value.offset === resource.size) { value.offset = 0; value.resource++; }
    } else { value.resource++; }
    value.job = undefined; value.sequence++; save(ctx, value);
    return json(progress(value));
  }
  if (value.resource > all.length) {
    // Re-read the actual recipient workspace files through the original-only
    // reader. A job exit or matching metadata is not byte-fidelity evidence.
    for (const resource of all) {
      await verifiedKnotWorkspaceFile(env, value.workspace, 'received/' + value.messageID + '/' + resource.path, resource.sha256, resource.size, signal);
      live(ctx, value, signal);
    }
    const entry = value.document.sourcePath!;
    const manifest = { path: entry, sha256: value.document.sha256, size: value.document.size, format: value.document.format, pages: value.document.pages, proofs: [], ...(value.document.bundle ? { bundle: { entry, assets: value.document.bundle.assets.map(({ resourceID: _id, ...asset }) => asset) } } : {}) };
    ctx.storage.transactionSync(() => {
      live(ctx, value!, signal); value!.done = true; save(ctx, value!);
      ctx.storage.sql.exec('UPDATE knot_documents SET bot=?,data=? WHERE id=?', 'main', JSON.stringify(value!.document), value!.document.id);
      ctx.storage.sql.exec('INSERT OR REPLACE INTO knot_document_sources VALUES (?,?,?)', value!.document.id, value!.workspace, JSON.stringify(manifest));
    });
    return json(progress(value));
  }
  const resource = all[value.resource];
  const chunk = resource ? knotStoredResource(ctx, value.document.id, resource.resource, value.offset, Math.min(48000, resource.size - value.offset)) : undefined;
  const command = artifactImportCommand(value, resource, chunk);
  value.job = { sequence: value.sequence }; save(ctx, value); // intent BEFORE I/O
  const response = await sidecarRequest(env, '/exec', 'POST', { user_id: value.workspace, command, background: true, timeout_ms: 30000 }, 12000, signal);
  const receipt = await parse(response, 16000);
  // The response is safe to retain even if the caller cancelled after dispatch;
  // erasure still wins and no continuation happens without a fresh Save call.
  if (state(ctx, value.messageID) && typeof receipt.job_id === 'string' && /^[a-zA-Z0-9_-]{1,160}$/.test(receipt.job_id)) {
    value.job.id = receipt.job_id; save(ctx, value);
  }
  return json(progress(value));
}
