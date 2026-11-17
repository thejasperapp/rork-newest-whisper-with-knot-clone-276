import { DurableObject } from 'cloudflare:workers';
import { knotBots } from './knot-agent';
import { normalizedKnotReaction } from './knot-message-skills';
import { reactionPreference } from './knot-reaction-policy';
import { validatedStoredClarification, validatedClarificationAnswer } from './knot-clarification';
import { dispatchKnotActor, type KnotShellEnv } from './knot-shell';

type Env = KnotShellEnv & { DO: Fetcher };
type Row = { id: string; bot: string; title: string; updated: number; deleted: number };
type Message = { id: string; role: 'user' | 'ember'; text: string; createdAt: number; modifiedAt: number; [key: string]: unknown };
type MessageRow = { id: string; created: number; modified: number; value: string };
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const headers = { 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Whisper-Authorization', 'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS' };
const json = (body: unknown, status = 200) => Response.json(body, { status, headers });
async function read(request: Request): Promise<Record<string, unknown>> {
  if (!request.body) throw new Error('body');
  const reader = request.body.getReader(), decoder = new TextDecoder();
  let text = '', size = 0;
  try { for (;;) { const part = await reader.read(); if (part.done) break; size += part.value.byteLength; if (size > 256000) throw new Error('size'); text += decoder.decode(part.value, { stream: true }); } }
  finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
  const value: unknown = JSON.parse(text + decoder.decode());
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('body');
  return value as Record<string, unknown>;
}

/** Private account history only. Stored metadata is display data, never approval
 * or evidence: execution routes independently verify their immutable records. */
export class KnotConversationAccount extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS chats (id TEXT PRIMARY KEY, bot TEXT NOT NULL, title TEXT NOT NULL, updated REAL NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)');
    ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS messages (chat TEXT NOT NULL, id TEXT NOT NULL, created REAL NOT NULL, modified REAL NOT NULL, value TEXT NOT NULL, PRIMARY KEY(chat,id))');
    ctx.storage.sql.exec('CREATE INDEX IF NOT EXISTS message_order ON messages(chat,created,id)');
    ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS reaction_turns (request TEXT PRIMARY KEY, chat TEXT NOT NULL, source TEXT NOT NULL, expires REAL NOT NULL, closed INTEGER NOT NULL, started REAL NOT NULL)');
    ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS reactions (chat TEXT NOT NULL, source TEXT NOT NULL, emoji TEXT NOT NULL, revision INTEGER NOT NULL, recorded TEXT NOT NULL, PRIMARY KEY(chat,source))');
    ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS reaction_events (id TEXT PRIMARY KEY, chat TEXT NOT NULL, recorded REAL NOT NULL, data TEXT NOT NULL)');
    ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS reaction_calls (id TEXT PRIMARY KEY, request TEXT NOT NULL, chat TEXT NOT NULL, data TEXT NOT NULL)');
    ctx.storage.sql.exec('CREATE INDEX IF NOT EXISTS reaction_call_request ON reaction_calls(request)');
    // Source latches outlive expiring request ledgers, just like message history.
    ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS reaction_source_placements (chat TEXT NOT NULL, source TEXT NOT NULL, origin TEXT NOT NULL, data TEXT NOT NULL, PRIMARY KEY(chat,source,origin))');
    ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS reaction_preferences (chat TEXT PRIMARY KEY, disabled INTEGER NOT NULL)');
    ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS owned_turn_bindings (task TEXT PRIMARY KEY, chat TEXT NOT NULL, source TEXT UNIQUE NOT NULL, reply TEXT UNIQUE NOT NULL, bot TEXT NOT NULL, state TEXT NOT NULL)');
    ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS owned_messages (chat TEXT NOT NULL, id TEXT NOT NULL, PRIMARY KEY(chat,id))');
    ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS owned_turn_releases (task TEXT PRIMARY KEY)');
  }
  override async fetch(request: Request): Promise<Response> {
    if (!uuid.test(request.headers.get('X-Knot-Owner') ?? '') || request.headers.get('X-Knot-Owner') !== this.ctx.id.name) return json({ error: 'sign_in_required' }, 401);
    const url = new URL(request.url), sql = this.ctx.storage.sql;
    const match = /^\/knot\/conversations\/([0-9a-f-]{36})$/.exec(url.pathname);
    try {
      if (url.pathname.startsWith('/internal/owned-turns/') && request.method === 'POST') {
        const body = await read(request), action = url.pathname.split('/').pop();
        if (typeof body.taskID !== 'string' || !uuid.test(body.taskID) || typeof body.conversationID !== 'string' || !uuid.test(body.conversationID) || typeof body.bot !== 'string' || !knotBots.includes(body.bot as typeof knotBots[number])) return json({ error: 'invalid_task' }, 400);
        const chat = body.conversationID.toLowerCase(), task = body.taskID.toLowerCase(), now = Date.now();
        return this.ctx.storage.transactionSync(() => {
          if (action === 'release') {
            sql.exec('INSERT OR IGNORE INTO owned_turn_releases VALUES (?)', task);
            sql.exec("UPDATE owned_turn_bindings SET state='closed' WHERE task=? AND chat=? AND state='reserved'", task, chat);
            return json({ ok: true });
          }
          if (sql.exec('SELECT 1 FROM owned_turn_releases WHERE task=?', task).toArray().length) return json({ error: 'task_closed' }, 410);
          const current = sql.exec<Row>('SELECT * FROM chats WHERE id=?', chat).toArray()[0];
          if (current?.deleted) return json({ error: 'conversation_deleted' }, 410);
          if (current && current.bot !== body.bot) return json({ error: 'bot_conflict' }, 409);
          type Binding = { task: string; chat: string; source: string; reply: string; bot: string; state: string };
          const binding = sql.exec<Binding>('SELECT * FROM owned_turn_bindings WHERE task=?', task).toArray()[0];
          const put = (m: Message) => {
            sql.exec('INSERT OR IGNORE INTO messages VALUES (?,?,?,?,?)', chat, m.id, m.createdAt, m.modifiedAt, JSON.stringify(m));
            sql.exec('INSERT OR IGNORE INTO owned_messages VALUES (?,?)', chat, m.id);
            sql.exec('INSERT INTO chats VALUES (?,?,?,?,0) ON CONFLICT(id) DO UPDATE SET updated=excluded.updated', chat, body.bot as string, current?.title ?? String(body.text ?? '').slice(0,48), Math.max(now, (current?.updated ?? 0) + 1));
          };
          if (action === 'reserve') {
            if (body.sourceMessageID !== task || typeof body.replyID !== 'string' || !uuid.test(body.replyID) || typeof body.text !== 'string' || !body.text || body.text.length > 16000) return json({ error: 'invalid_task_source' }, 400);
            if (binding) return binding.chat === chat && binding.bot === body.bot && binding.source === task && binding.reply === body.replyID && binding.state === 'reserved' ? json({ ok: true }) : json({ error: 'task_already_closed' }, 409);
            const prior = sql.exec<MessageRow>('SELECT id,created,modified,value FROM messages WHERE chat=? AND id=?', chat, task).toArray()[0];
            if (prior && (JSON.parse(prior.value).role !== 'user' || JSON.parse(prior.value).text !== body.text)) return json({ error: 'source_conflict' }, 409);
            if (sql.exec('SELECT 1 FROM messages WHERE chat=? AND id=?', chat, body.replyID).toArray().length || sql.exec('SELECT 1 FROM owned_messages WHERE chat=? AND id IN (?,?)', chat, task, body.replyID).toArray().length) return json({ error: 'message_identity_conflict' }, 409);
            const total = sql.exec<{ n: number; bytes: number }>('SELECT COUNT(*) AS n,COALESCE(SUM(LENGTH(CAST(value AS BLOB))),0) AS bytes FROM messages').one();
            const reserved = sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM owned_turn_bindings WHERE state='reserved'").one().n;
            if ((!current && sql.exec<{ n: number }>('SELECT COUNT(*) AS n FROM chats WHERE deleted=0').one().n >= 200) || total.n + reserved * 3 + 3 > 20000 || total.bytes + reserved * 300000 + 400000 > 20000000) return json({ error: 'history_capacity' }, 507);
            const createdAt = typeof body.createdAt === 'number' && Number.isFinite(body.createdAt) && body.createdAt > 0 && body.createdAt <= now + 300000 ? body.createdAt : now;
            if (!prior) put({ id: task, role: 'user', text: body.text, createdAt, modifiedAt: createdAt });
            sql.exec('INSERT OR IGNORE INTO owned_messages VALUES (?,?)', chat, task);
            sql.exec('INSERT OR IGNORE INTO owned_messages VALUES (?,?)', chat, body.replyID);
            sql.exec('INSERT INTO owned_turn_bindings VALUES (?,?,?,?,?,?)', task, chat, task, body.replyID, body.bot as string, 'reserved');
            return json({ ok: true });
          }
          if (!binding || binding.chat !== chat || binding.bot !== body.bot) return json({ error: 'task_unavailable' }, 409);
          if (binding.state === 'silent' && action === 'deliver' && body.silent === true && body.replyID === binding.reply && body.text === '' && body.clarification == null) return json({ ok: true, silent: true });
          if (!['reserved','delivered'].includes(binding.state)) return json({ error: 'task_closed' }, 410);
          if (action === 'deliver') {
            if (body.replyID !== binding.reply || typeof body.text !== 'string' || body.text.length > 64000 || (!body.text.trim() && body.silent !== true) || (body.silent === true && (body.text !== '' || body.clarification != null))) return json({ error: 'invalid_task_reply' }, 400);
            if (body.silent === true) {
              // Explicit source-bound terminal acknowledgment, without inventing
              // a message. The same terminal binding makes retries idempotent.
              if (binding.state === 'delivered') return json({ error: 'reply_already_delivered' }, 409);
              sql.exec("UPDATE owned_turn_bindings SET state='silent' WHERE task=?", task);
              return json({ ok: true, silent: true });
            }
            const clarification = validatedStoredClarification(body.clarification, { conversationID: chat, bot: body.bot as string, role: 'ember', text: body.text });
            const createdAt = typeof body.createdAt === 'number' && Number.isFinite(body.createdAt) && body.createdAt > 0 && body.createdAt <= now + 300000 ? body.createdAt : now;
            put({ id: binding.reply, role: 'ember', text: body.text, createdAt, modifiedAt: createdAt, serverTaskID: task, ...(clarification ? { clarification } : {}) });
            sql.exec("UPDATE owned_turn_bindings SET state='delivered' WHERE task=?", task);
            return json({ ok: true });
          }
          if (action === 'calculation') {
            const c = body.calculation as Record<string,unknown> | undefined;
            if (!c || typeof c.id !== 'string' || !uuid.test(c.id) || c.id === binding.reply || c.id === task || c.conversationID !== chat || c.sourceMessageID !== task || typeof c.expression !== 'string' || c.expression.length > 2000 || typeof c.value !== 'number' || !Number.isFinite(c.value) || typeof c.completedAt !== 'number' || !Number.isFinite(c.completedAt) || JSON.stringify(c).length > 50000) return json({ error: 'invalid_calculation' }, 400);
            const previous = sql.exec<{ value: string }>('SELECT value FROM messages WHERE chat=? AND id=?', chat, c.id).toArray()[0];
            if (previous) return JSON.parse(previous.value).serverTaskID === task && JSON.parse(previous.value).calculation?.id === c.id ? json({ ok: true }) : json({ error: 'message_identity_conflict' }, 409);
            if (sql.exec("SELECT 1 FROM messages WHERE chat=? AND json_extract(value,'$.serverTaskID')=? AND json_extract(value,'$.calculation') IS NOT NULL", chat, task).toArray().length) return json({ error: 'calculation_capacity' }, 409);
            put({ id: c.id, role: 'ember', text: '', createdAt: now, modifiedAt: now, calculation: c, serverTaskID: task }); return json({ ok: true });
          }
          return json({ error: 'not_found' }, 404);
        });
      }
      if (url.pathname.startsWith('/internal/reactions/')) {
        const body = await read(request), action = url.pathname.split('/').pop();
        if (request.method !== 'POST' || typeof body.conversationID !== 'string' || !uuid.test(body.conversationID) || typeof body.bot !== 'string' || !knotBots.includes(body.bot as typeof knotBots[number])) return json({ error: 'invalid_reaction_context' }, 400);
        const chat = body.conversationID.toLowerCase(), now = Date.now();
        sql.exec('DELETE FROM reaction_calls WHERE request IN (SELECT request FROM reaction_turns WHERE expires < ?)', now - 86400000);
        sql.exec('DELETE FROM reaction_turns WHERE expires < ?', now - 86400000);
        sql.exec('DELETE FROM reaction_events WHERE recorded < ?', now - 86400000);
        const current = sql.exec<Row>('SELECT * FROM chats WHERE id=?', chat).toArray()[0];
        if (current?.deleted || (current && current.bot !== body.bot)) return json({ error: 'reaction_context_unavailable' }, 409);
        if (action === 'events') return json({ activities: sql.exec<{ data: string }>('SELECT data FROM reaction_events WHERE chat=? ORDER BY recorded DESC,id DESC LIMIT 400', chat).toArray().map(row => JSON.parse(row.data)) });
        if (typeof body.requestID !== 'string' || !uuid.test(body.requestID) || typeof body.sourceMessageID !== 'string' || !uuid.test(body.sourceMessageID)) return json({ error: 'invalid_reaction_turn' }, 400);
        const requestID = body.requestID.toLowerCase(), source = body.sourceMessageID.toLowerCase();
        type Lease = { request: string; chat: string; source: string; expires: number; closed: number; started: number };
        const lease = () => sql.exec<Lease>('SELECT * FROM reaction_turns WHERE request=?', requestID).toArray()[0];
        const activity = (kind: string, label: string, identity: string, emoji?: string, revision?: number) => {
          const value = { id: identity, requestID, taskID: requestID, sourceMessageID: source, messageID: source, sequence: revision ?? 1, kind, label, emoji, revision, recordedAt: new Date(now).toISOString() };
          sql.exec('INSERT OR IGNORE INTO reaction_events VALUES (?,?,?,?)', identity, chat, now, JSON.stringify(value));
          sql.exec('DELETE FROM reaction_events WHERE id IN (SELECT id FROM reaction_events ORDER BY recorded DESC,id DESC LIMIT -1 OFFSET 2400)');
        };
        const semanticAllowed = () => sql.exec<{ disabled: number }>('SELECT disabled FROM reaction_preferences WHERE chat=?', chat).toArray()[0]?.disabled !== 1;
        if (action === 'close') { sql.exec('UPDATE reaction_turns SET closed=1 WHERE request=? AND chat=? AND source=?', requestID, chat, source); return json({ closed: true }); }
        if (action === 'begin') return this.ctx.storage.transactionSync(() => {
          if (lease()) return json({ error: 'reaction_turn_already_seen' }, 409);
          if (sql.exec('SELECT 1 FROM reaction_turns WHERE chat=? AND source=? AND closed=0 AND expires>?', chat, source, now).toArray().length) return json({ error: 'reaction_turn_active' }, 409);
          if (typeof body.text !== 'string' || !body.text || body.text.length > 16000) return json({ error: 'invalid_reaction_source' }, 400);
          const prior = sql.exec<MessageRow>('SELECT id,created,modified,value FROM messages WHERE chat=? AND id=?', chat, source).toArray()[0];
          if (prior) { const m = JSON.parse(prior.value) as Message; if (m.role !== 'user' || m.text !== body.text) return json({ error: 'reaction_source_conflict' }, 409); }
          if (!current && sql.exec<{ n: number }>('SELECT COUNT(*) AS n FROM chats WHERE deleted=0').one().n >= 200) return json({ error: 'history_capacity' }, 507);
          if (!prior) {
            const total = sql.exec<{ n: number; bytes: number }>('SELECT COUNT(*) AS n,COALESCE(SUM(LENGTH(CAST(value AS BLOB))),0) AS bytes FROM messages').one();
            if (total.n >= 20000 || total.bytes + 100000 > 20000000) return json({ error: 'history_capacity' }, 507);
            const created = typeof body.createdAt === 'number' && Number.isFinite(body.createdAt) && body.createdAt > 0 && body.createdAt <= now + 300000 ? body.createdAt : now;
            const m = { id: source, role: 'user', text: body.text, createdAt: created, modifiedAt: created };
            sql.exec('INSERT INTO messages VALUES (?,?,?,?,?)', chat, source, created, created, JSON.stringify(m));
          }
          sql.exec('INSERT INTO chats VALUES (?,?,?,?,0) ON CONFLICT(id) DO UPDATE SET updated=excluded.updated', chat, body.bot as string, current?.title ?? (body.text as string).slice(0,48), Math.max(now, (current?.updated ?? 0) + 1));
          const preference = reactionPreference(body.text);
          if (preference) sql.exec('INSERT OR REPLACE INTO reaction_preferences VALUES (?,?)', chat, preference === 'off' ? 1 : 0);
          const ready = body.supported === true && semanticAllowed();
          // Runtime work acknowledgment is independent of semantic preferences.
          sql.exec('INSERT INTO reaction_turns VALUES (?,?,?,?,?,?)', requestID, chat, source, now + 900000, body.supported === true ? 0 : 2, now);
          if (body.supported !== true) activity('reaction_unsupported', 'This client cannot display live reactions', requestID + ':reaction-unsupported');
          return json({ ready, runtimeReady: body.supported === true, suppressed: body.supported === true && !ready });
        });
        if (action === 'apply') return this.ctx.storage.transactionSync(() => {
          const turn = lease();
          if (!turn || turn.chat !== chat || turn.source !== source || turn.closed || turn.expires <= now || body.messageID !== source || typeof body.callID !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(body.callID) || !normalizedKnotReaction(body.emoji)) return json({ error: 'reaction_turn_expired_or_invalid' }, 409);
          const origin = body.origin ?? 'semantic';
          if (!['semantic', 'runtime_long_work'].includes(String(origin)) || (origin === 'runtime_long_work' && body.emoji !== '👍')) return json({ error: 'invalid_reaction_origin' }, 400);
          const identity = requestID + ':reaction:' + body.callID;
          // Retain no-op call identities too: reusing one after A → B cannot
          // accidentally restore A. Older applied calls remain in the event ledger.
          const existing = sql.exec<{ data: string }>('SELECT data FROM reaction_calls WHERE id=?', identity).toArray()[0]
            ?? sql.exec<{ data: string }>('SELECT data FROM reaction_events WHERE id=?', identity).toArray()[0];
          if (existing) { const e = JSON.parse(existing.data); return e.emoji === body.emoji && (e.origin ?? 'semantic') === origin ? json({ messageID: source, emoji: e.emoji, revision: e.revision, recordedAt: e.recordedAt, changed: false }) : json({ error: 'reaction_call_conflict' }, 409); }
          const row = sql.exec<MessageRow>('SELECT id,created,modified,value FROM messages WHERE chat=? AND id=?', chat, source).toArray()[0];
          if (!current || !row || (JSON.parse(row.value) as Message).role !== 'user') return json({ error: 'reaction_source_missing' }, 409);
          const old = sql.exec<{ emoji: string; revision: number; recorded: string }>('SELECT emoji,revision,recorded FROM reactions WHERE chat=? AND source=?', chat, source).toArray()[0];
          if (origin === 'semantic' && !semanticAllowed()) return json({ error: 'reaction_suppressed' }, 409);
          const placement = (kind: string) => sql.exec<{ data: string }>('SELECT data FROM reaction_source_placements WHERE chat=? AND source=? AND origin=?', chat, source, kind).toArray()[0];
          const runtime = placement('runtime_long_work');
          // Conservatively retain pre-latch placements as semantic decisions.
          const semantic = placement('semantic') ?? (!runtime && old ? { data: JSON.stringify({ emoji: old.emoji, revision: old.revision, recordedAt: old.recorded }) } : undefined);
          const latched = origin === 'semantic' ? semantic : semantic ?? runtime;
          if (latched) {
            const prior = JSON.parse(latched.data);
            return origin === 'runtime_long_work' || prior.emoji === body.emoji ? json({ messageID: source, emoji: prior.emoji, revision: prior.revision, recordedAt: prior.recordedAt, changed: false }) : json({ error: 'source_reaction_already_authored' }, 409);
          }
          if (sql.exec<{ n: number }>('SELECT COUNT(*) AS n FROM reaction_calls WHERE request=?', requestID).one().n >= 64 || sql.exec<{ n: number }>('SELECT COUNT(*) AS n FROM reaction_calls').one().n >= 20000) return json({ error: 'reaction_call_capacity' }, 409);
          const remember = (emoji: string, revision: number, recordedAt: string) => {
            const data = JSON.stringify({ emoji, revision, recordedAt, source, origin });
            sql.exec('INSERT INTO reaction_calls VALUES (?,?,?,?)', identity, requestID, chat, data);
            sql.exec('INSERT OR IGNORE INTO reaction_source_placements VALUES (?,?,?,?)', chat, source, origin, data);
          };
          // Latch by the actual message and current emoji, not a model call ID.
          // No revision/history/event write means no repeated presentation effect.
          if (old?.emoji === body.emoji) {
            remember(old.emoji, old.revision, old.recorded);
            return json({ messageID: source, emoji: old.emoji, revision: old.revision, recordedAt: old.recorded, changed: false });
          }
          const revision = (old?.revision ?? 0) + 1, recordedAt = new Date(now).toISOString();
          remember(body.emoji as string, revision, recordedAt);
          sql.exec('INSERT OR REPLACE INTO reactions VALUES (?,?,?,?,?)', chat, source, body.emoji as string, revision, recordedAt);
          const modified = Math.max(now, row.modified + 1);
          const m = { ...JSON.parse(row.value), reaction: body.emoji, reactionRevision: revision, reactionRecordedAt: recordedAt, modifiedAt: modified };
          sql.exec('UPDATE messages SET value=?,modified=? WHERE chat=? AND id=?', JSON.stringify(m), modified, chat, source);
          sql.exec('UPDATE chats SET updated=? WHERE id=?', Math.max(now, current.updated + 1), chat);
          activity(old ? 'reaction_replaced' : 'reaction_placed', old ? 'Knot reaction replaced' : 'Knot reaction placed', identity, body.emoji as string, revision);
          return json({ messageID: source, emoji: body.emoji, revision, recordedAt, changed: true });
        });
        return json({ error: 'not_found' }, 404);
      }
      if (url.pathname === '/knot/conversations' && request.method === 'GET') {
        // ID ordering is stable while another device changes update timestamps.
        const after = url.searchParams.get('after') ?? '';
        if (after && !uuid.test(after)) return json({ error: 'invalid_cursor' }, 400);
        const rows = sql.exec<Row>('SELECT * FROM chats WHERE id > ? ORDER BY id LIMIT 51', after).toArray();
        const page = rows.slice(0, 50);
        return json({ conversations: page.map(row => ({ id: row.id, botID: row.bot, title: row.title, updatedAt: row.updated, deleted: !!row.deleted })), next: rows.length > 50 ? page.at(-1)!.id : null });
      }
      if (!match || !uuid.test(match[1])) return json({ error: 'not_found' }, 404);
      const id = match[1].toLowerCase();
      const current = () => sql.exec<Row>('SELECT * FROM chats WHERE id = ?', id).toArray()[0];
      if (request.method === 'DELETE') {
        this.ctx.storage.transactionSync(() => {
          sql.exec("INSERT INTO chats VALUES (?, 'main', '', ?, 1) ON CONFLICT(id) DO UPDATE SET title='',updated=excluded.updated,deleted=1 WHERE chats.deleted=0", id, Date.now());
          sql.exec('DELETE FROM messages WHERE chat = ?', id);
          sql.exec('DELETE FROM owned_messages WHERE chat=?', id);
          sql.exec("UPDATE owned_turn_bindings SET state='deleted' WHERE chat=?", id);
          sql.exec('DELETE FROM reactions WHERE chat = ?', id);
          sql.exec('DELETE FROM reaction_preferences WHERE chat = ?', id);
          sql.exec('DELETE FROM reaction_events WHERE chat = ?', id);
          sql.exec('DELETE FROM reaction_calls WHERE chat = ?', id);
          sql.exec('DELETE FROM reaction_source_placements WHERE chat = ?', id);
          sql.exec('UPDATE reaction_turns SET closed=1 WHERE chat = ?', id);
        });
        return json({ ok: true });
      }
      if (request.method === 'GET') {
        const row = current();
        if (!row || row.deleted) return json({ error: row?.deleted ? 'conversation_deleted' : 'not_found' }, row?.deleted ? 410 : 404);
        const after = Number(url.searchParams.get('after') ?? '0'), afterID = url.searchParams.get('afterID') ?? '';
        if (!Number.isFinite(after) || after < 0 || (afterID && !uuid.test(afterID))) return json({ error: 'invalid_cursor' }, 400);
        const rows = sql.exec<MessageRow>('SELECT id,created,modified,value FROM messages WHERE chat = ? AND (created > ? OR (created = ? AND id > ?)) ORDER BY created,id LIMIT 26', id, after, after, afterID).toArray();
        const page: MessageRow[] = []; let bytes = 0;
        for (const item of rows.slice(0,25)) { const size = new TextEncoder().encode(item.value).byteLength; if (bytes + size > 180000 && page.length) break; bytes += size; page.push(item); }
        return json({ messages: page.map(item => JSON.parse(item.value)), next: rows.length > page.length && page.length ? { after: page.at(-1)!.created, afterID: page.at(-1)!.id } : null });
      }
      if (request.method === 'POST') {
        const body = await read(request);
        if (typeof body.botID !== 'string' || !knotBots.includes(body.botID as typeof knotBots[number]) || typeof body.title !== 'string' || body.title.length > 160 || !Array.isArray(body.messages) || body.messages.length > 25) return json({ error: 'invalid_conversation' }, 400);
        const now = Date.now();
        const messages: Message[] = [];
        for (const raw of body.messages) {
          const m = raw as Message;
          if (!m || typeof m !== 'object' || typeof m.id !== 'string' || !uuid.test(m.id) || !['user','ember'].includes(m.role) || typeof m.text !== 'string' || m.text.length > 64000 || typeof m.createdAt !== 'number' || !Number.isFinite(m.createdAt) || m.createdAt <= 0 || m.createdAt > now + 300000 || typeof m.modifiedAt !== 'number' || !Number.isFinite(m.modifiedAt) || m.modifiedAt < m.createdAt || m.modifiedAt > now + 300000 || new TextEncoder().encode(JSON.stringify(m)).byteLength > 100000) return json({ error: 'invalid_message' }, 400);
          // No ownership, permissions, execution grants or client tool dispatch are stored.
          const { id: messageID, role, text, createdAt, modifiedAt, sharedPostIDs, sharedCommunityIDs, backgroundMessageID, responsibility, shell, proposals, browserPreview, replyTo, interrupted } = m;
          const clarification = validatedStoredClarification(m.clarification, { conversationID: id, bot: body.botID as string, role, text });
          const clarificationAnswer = validatedClarificationAnswer(m.clarificationAnswer, role, text);
          let identity = messageID.toLowerCase();
          if (backgroundMessageID !== undefined) {
            if (typeof backgroundMessageID !== 'string' || backgroundMessageID.length > 200) return json({ error: 'invalid_message' }, 400);
            const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode('background:' + backgroundMessageID));
            const hex = Array.from(new Uint8Array(digest).slice(0,16), b => b.toString(16).padStart(2,'0')).join('');
            identity = `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
          }
          // Bounded private reply metadata is display/context only. It cannot
          // identify another chat, import approval, or supply an execution receipt.
          let replyReference: { messageID: string; role: string; preview: string } | undefined;
          if (replyTo !== undefined && replyTo !== null) {
            if (role !== 'user' || typeof replyTo !== 'object' || Array.isArray(replyTo)) return json({ error: 'invalid_reply' }, 400);
            const quote = replyTo as Record<string, unknown>;
            if (Object.keys(quote).some(key => !['messageID', 'role', 'preview'].includes(key)) || typeof quote.messageID !== 'string' || !uuid.test(quote.messageID) || quote.messageID.toLowerCase() === identity || !['user', 'ember'].includes(quote.role as string) || typeof quote.preview !== 'string' || !quote.preview.trim() || quote.preview.length > 600) return json({ error: 'invalid_reply' }, 400);
            replyReference = { messageID: quote.messageID.toLowerCase(), role: quote.role as string, preview: quote.preview };
          }
          // Syncing a command draft never imports a claimed execution receipt.
          const shellDraft = shell && typeof shell === 'object' && !Array.isArray(shell) && (shell as Record<string, unknown>).spec
            ? { spec: (shell as Record<string, unknown>).spec, state: 'expired', continued: false } : undefined;
          messages.push({ id: identity, role, text, createdAt, modifiedAt, sharedPostIDs, sharedCommunityIDs, backgroundMessageID, responsibility, shell: shellDraft, proposals, ...(browserPreview === true ? { browserPreview: true } : {}), ...(replyReference ? { replyTo: replyReference } : {}), ...(role === 'ember' && interrupted === true ? { interrupted: true } : {}), ...(clarification ? { clarification } : {}), ...(clarificationAnswer ? { clarificationAnswer } : {}) });
        }
        return this.ctx.storage.transactionSync(() => {
          const old = current();
          if (old?.deleted) return json({ error: 'conversation_deleted' }, 410);
          if (old && old.bot !== body.botID) return json({ error: 'bot_conflict' }, 409);
          const count = sql.exec<{ n: number }>('SELECT COUNT(*) AS n FROM chats WHERE deleted=0').one().n;
          if (!old && count >= 200) return json({ error: 'history_capacity' }, 507);
          const total = sql.exec<{ n: number; bytes: number }>('SELECT COUNT(*) AS n, COALESCE(SUM(LENGTH(CAST(value AS BLOB))),0) AS bytes FROM messages').one();
          const changes = new Map<string, { message: Message; value: string; prior?: MessageRow }>();
          for (const raw of messages) {
            // Immutable server deliveries cannot be overwritten by a late
            // provisional/older-device history upload, regardless of its clock.
            if (sql.exec('SELECT 1 FROM owned_messages WHERE chat=? AND id=?', id, raw.id).toArray().length) {
              const source = sql.exec<MessageRow>('SELECT id,created,modified,value FROM messages WHERE chat=? AND id=?', id, raw.id).toArray()[0];
              const stored = source ? JSON.parse(source.value) as Message : undefined;
              // Source text/identity are immutable, but late quote metadata from
              // the original send must survive the admission/upload race.
              if (source && stored?.role === 'user' && raw.role === 'user' && raw.text === stored.text && ((!stored.replyTo && raw.replyTo) || (!stored.clarificationAnswer && raw.clarificationAnswer) || (stored.browserPreview !== true && raw.browserPreview === true))) {
                const message: Message = { ...stored, ...(!stored.replyTo && raw.replyTo ? { replyTo: raw.replyTo } : {}), ...(!stored.clarificationAnswer && raw.clarificationAnswer ? { clarificationAnswer: raw.clarificationAnswer } : {}), ...(raw.browserPreview === true ? { browserPreview: true } : {}), modifiedAt: Math.max(now, stored.modifiedAt + 1) };
                changes.set(raw.id, { message, value: JSON.stringify(message), prior: source });
              }
              continue;
            }
            const prior = changes.get(raw.id)?.prior ?? sql.exec<MessageRow>('SELECT id,created,modified,value FROM messages WHERE chat=? AND id=?', id, raw.id).toArray()[0];
            if (raw.modifiedAt <= (changes.get(raw.id)?.message.modifiedAt ?? prior?.modified ?? 0)) {
              const stored = changes.get(raw.id)?.message ?? (prior ? JSON.parse(prior.value) as Message : undefined);
              // A reaction may commit between history read and upload. Attach
              // missing immutable display metadata without replacing its text,
              // reaction, or stronger timestamp with an older client snapshot.
              if (stored && stored.role === raw.role && stored.text === raw.text && ((!stored.replyTo && raw.role === 'user' && raw.replyTo) || (stored.interrupted !== true && raw.role === 'ember' && raw.interrupted === true) || (!stored.clarification && raw.clarification) || (!stored.clarificationAnswer && raw.clarificationAnswer))) {
                const message = { ...stored, ...(!stored.replyTo && raw.replyTo ? { replyTo: raw.replyTo } : {}), ...(raw.interrupted === true ? { interrupted: true } : {}), ...(!stored.clarification && raw.clarification ? { clarification: raw.clarification } : {}), ...(!stored.clarificationAnswer && raw.clarificationAnswer ? { clarificationAnswer: raw.clarificationAnswer } : {}), modifiedAt: Math.max(now, stored.modifiedAt + 1) };
                changes.set(raw.id, { message, value: JSON.stringify(message), prior });
              }
              continue;
            }
            if (prior && (JSON.parse(prior.value) as Message).role !== raw.role) return json({ error: 'message_conflict' }, 409);
            // Re-read INSIDE this transaction: an apply may have committed while
            // a background identity digest yielded above. Client metadata never wins.
            const authority = sql.exec<{ emoji: string; revision: number; recorded: string }>('SELECT emoji,revision,recorded FROM reactions WHERE chat=? AND source=?', id, raw.id).toArray()[0];
            const oldMessage = prior ? JSON.parse(prior.value) as Message : undefined;
            const sameText = oldMessage?.text === raw.text;
            const message = { ...raw, createdAt: prior?.created ?? raw.createdAt, reaction: authority?.emoji, reactionRevision: authority?.revision, reactionRecordedAt: authority?.recorded,
              ...(sameText && raw.role === 'user' && oldMessage?.replyTo ? { replyTo: oldMessage.replyTo } : {}),
              ...(sameText && raw.role === 'ember' && oldMessage?.interrupted === true ? { interrupted: true } : {}),
              ...(sameText && oldMessage?.clarification ? { clarification: oldMessage.clarification } : {}),
              ...(sameText && oldMessage?.clarificationAnswer ? { clarificationAnswer: oldMessage.clarificationAnswer } : {}) };

            changes.set(raw.id, { message, value: JSON.stringify(message), prior });
          }
          let additions = 0, bytes = total.bytes;
          for (const change of changes.values()) { if (!change.prior) additions++; bytes += new TextEncoder().encode(change.value).byteLength - (change.prior ? new TextEncoder().encode(change.prior.value).byteLength : 0); }
          const reservations = sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM owned_turn_bindings WHERE state='reserved'").one().n;
          if (total.n + additions + reservations * 3 > 20000 || bytes + reservations * 300000 > 20000000) return json({ error: 'history_capacity' }, 507);
          if (!old || changes.size) {
            const updated = Math.max(now, (old?.updated ?? 0) + 1);
            sql.exec('INSERT INTO chats VALUES (?,?,?,?,0) ON CONFLICT(id) DO UPDATE SET title=excluded.title,updated=excluded.updated', id, body.botID as string, body.title as string, updated);
          }
          for (const { message, value } of changes.values()) {
            sql.exec('INSERT INTO messages VALUES (?,?,?,?,?) ON CONFLICT(chat,id) DO UPDATE SET value=excluded.value,modified=excluded.modified', id, message.id, message.createdAt, message.modifiedAt, value);
          }
          return json({ ok: true });
        });
      }
      return json({ error: 'method_not_allowed' }, 405);
    } catch { return json({ error: 'history_unavailable' }, 400); }
  }
}
export async function knotConversationsRoute(request: Request, env: Env, userID: string): Promise<Response> {
  const owner = userID.toLowerCase();
  const deleted = /^\/knot\/conversations\/([0-9a-f-]{36})$/i.exec(new URL(request.url).pathname);
  if (request.method === 'DELETE' && deleted && uuid.test(deleted[1])) {
    // Tombstone delivery before history deletion; late captures cannot resurrect
    // files. Repeated deletion remains safe if the history request later fails.
    const stopped = await env.DO.fetch(new Request('https://internal/internal/owned-turns/erase', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Knot-Owner': owner, 'X-Rork-DO-Class': 'KnotBackgroundAccount', 'X-Rork-DO-Id': owner }, body: JSON.stringify({ conversationID: deleted[1].toLowerCase() }) }));
    await stopped.body?.cancel();
    if (!stopped.ok) return json({ error: 'task_stop_unavailable' }, 503);
    const erased = await dispatchKnotActor(env, owner, 'documents/erase-conversation', { conversationID: deleted[1].toLowerCase() });
    await erased.body?.cancel();
    if (!erased.ok) return json({ error: 'document_deletion_unavailable' }, 503);
  }
  // Never proxy internal verbs supplied in a public URL.
  if (!/^\/knot\/conversations(?:\/[0-9a-f-]{36})?$/.test(new URL(request.url).pathname)) return json({ error: 'not_found' }, 404);
  return env.DO.fetch(new Request(new Request(request.url, request), { headers: { 'Content-Type': 'application/json', 'X-Knot-Owner': owner, 'X-Rork-DO-Class': 'KnotConversationAccount', 'X-Rork-DO-Id': owner } }));
}
