// @vitest-environment node
// Synthetic SQLite metadata only. Never capture or execute an existing command.
import { afterEach, describe, expect, it, vi } from 'vitest';
import { DatabaseSync } from 'node:sqlite';
vi.mock('cloudflare:workers', () => ({ DurableObject: class { constructor(protected ctx: unknown, protected env: unknown) {} } }));
import { KnotShellConversation } from '../../functions/knot-shell';
import { attachKnotDeliveryNote, ownedKnotDocument, type KnotDocument } from '../../functions/knot-documents';

const id = (n: number) => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');
const databases: DatabaseSync[] = [];
afterEach(() => { for (const db of databases.splice(0)) db.close(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });
function fixture() {
  const db = new DatabaseSync(':memory:'); databases.push(db);
  const sql = { exec(query: string, ...values: (string | number | null)[]) {
    const statement = db.prepare(query), rows = statement.columns().length ? statement.all(...values) : (statement.run(...values), []);
    return { toArray: () => rows, one: () => { if (rows.length !== 1) throw new Error('Expected one SQL row'); return rows[0]; }, [Symbol.iterator]: () => rows[Symbol.iterator]() };
  } };
  const ctx = { storage: { sql, transactionSync: (f: () => unknown) => { db.exec('BEGIN'); try { const value = f(); db.exec('COMMIT'); return value; } catch (error) { db.exec('ROLLBACK'); throw error; } }, getAlarm: async () => null, setAlarm: async () => undefined } } as never;
  const network = vi.fn(async () => { throw new Error('External execution forbidden'); }); vi.stubGlobal('fetch', network);
  const actor = new KnotShellConversation(ctx, { DO: { fetch: network }, SIDECAR_TOKEN_WHISPER: 'synthetic-only' });
  const binding = { bot: 'main', conversationID: id(1), sourceMessageID: id(2), proposalID: id(3), documentID: 'a'.repeat(64), sha256: 'b'.repeat(64) };
  const document: KnotDocument = { id: binding.documentID, name: 'route.pdf', title: 'Route Guide', format: 'pdf', contentType: 'application/pdf', size: 100, sha256: binding.sha256, pages: 2, proofPages: [1], createdAt: '2026-11-15T00:00:00Z', expiresAt: '2026-11-22T00:00:00Z', proposalID: binding.proposalID, review: 'unavailable', sampled: true, sourceMessageID: binding.sourceMessageID };
  const seed = (doc: KnotDocument) => {
    sql.exec('INSERT INTO knot_documents VALUES (?,?,?,?,?,?)', doc.id, binding.bot, binding.conversationID, Date.now() + 600000, doc.size, JSON.stringify(doc));
    db.prepare('INSERT INTO knot_document_bytes VALUES (?,0,0,?)').run(doc.id, new Uint8Array([1, 2, 3]));
    sql.exec('INSERT INTO knot_document_sources VALUES (?,?,?)', doc.id, 'synthetic-workspace', '{"source":"unchanged"}');
  };
  seed(document);
  const record = { proposal: { id: binding.proposalID, bot: binding.bot, conversationID: binding.conversationID }, phase: 'finished', logFinal: true, cancelled: false, workflow: { rootID: id(4), sourceMessageID: binding.sourceMessageID } };
  sql.exec('INSERT INTO shell_records VALUES (?,?)', binding.proposalID, JSON.stringify(record));
  const post = (path: string, body: unknown) => actor.fetch(new Request('https://internal/' + path, { method: 'POST', body: JSON.stringify(body) }));
  const read = () => ownedKnotDocument(ctx, binding.bot, binding.conversationID, document.id);
  return { db, sql, ctx, actor, network, binding, document, seed, record, post, read };
}

describe('source-bound immutable file delivery notes', () => {
  it('binds every identity dimension and preserves the first note without modifying bytes or reviews', () => {
    const f = fixture();
    for (const key of Object.keys(f.binding) as (keyof typeof f.binding)[]) {
      expect(attachKnotDeliveryNote(f.ctx, { ...f.binding, [key]: 'wrong' }, 'A specific review.')).toBeUndefined();
      expect(f.read()).toEqual(f.document);
    }
    const beforeBytes = f.sql.exec('SELECT * FROM knot_document_bytes').toArray();
    const beforeSources = f.sql.exec('SELECT * FROM knot_document_sources').toArray();
    const beforeRow = f.sql.exec('SELECT id,bot,conversation_id,expires,bytes FROM knot_documents').toArray();
    const note = 'Route Guide covers the trail in two pages. Page-image review is unavailable; facts were not certified.';
    expect(attachKnotDeliveryNote(f.ctx, f.binding, note)).toEqual({ ...f.document, deliveryNote: note });
    expect(attachKnotDeliveryNote(f.ctx, f.binding, 'A later replacement.')).toEqual({ ...f.document, deliveryNote: note });
    expect(f.sql.exec('SELECT * FROM knot_document_bytes').toArray()).toEqual(beforeBytes);
    expect(f.sql.exec('SELECT * FROM knot_document_sources').toArray()).toEqual(beforeSources);
    expect(f.sql.exec('SELECT id,bot,conversation_id,expires,bytes FROM knot_documents').toArray()).toEqual(beforeRow);
    expect(f.network).not.toHaveBeenCalled();
  });
  it('persists two independent file reviews even under the same source and proposal', () => {
    const f = fixture(), other = { ...f.document, id: 'c'.repeat(64), sha256: 'd'.repeat(64), name: 'packing.pdf', title: 'Packing List' };
    f.seed(other);
    attachKnotDeliveryNote(f.ctx, f.binding, 'Route Guide: trail and timing. Visual review remains unavailable.');
    attachKnotDeliveryNote(f.ctx, { ...f.binding, documentID: other.id, sha256: other.sha256 }, 'Packing List: equipment checklist. Facts remain unverified.');
    expect(f.read()?.deliveryNote).toContain('trail and timing');
    expect(ownedKnotDocument(f.ctx, 'main', f.binding.conversationID, other.id)?.deliveryNote).toContain('equipment checklist');
    expect(f.network).not.toHaveBeenCalled();
  });
  it.each(['conversation', 'account'])('refuses note attachment after %s deletion', scope => {
    const f = fixture();
    f.sql.exec('INSERT INTO knot_document_deletions VALUES (?)', scope === 'account' ? '*' : f.binding.conversationID);
    expect(attachKnotDeliveryNote(f.ctx, f.binding, 'A review.')).toBeUndefined();
    expect(f.read()).toEqual(f.document);
  });
  it('rejects unsafe prose without invalidating the captured document', () => {
    const f = fixture();
    for (const note of [null, '', ' ', ' padded', 'x'.repeat(1201), '<control>', '`command`', 'First\nSecond', '\u0000']) {
      expect(attachKnotDeliveryNote(f.ctx, f.binding, note)).toBeUndefined();
      expect(f.read()).toEqual(f.document);
    }
    expect(attachKnotDeliveryNote(f.ctx, f.binding, 'x'.repeat(1200))?.deliveryNote).toHaveLength(1200);
  });
  it('accepts only an owned finished receipt and refuses a stopped root without external work', async () => {
    const f = fixture(), payload = { ...f.binding, note: 'Route Guide: two pages. Runtime was not tested.' };
    expect((await f.post('documents/delivery-note', payload)).status).toBe(200);
    const stopped = fixture();
    expect((await stopped.post('activity', { bot: 'main', conversationID: id(1), requestID: id(5), taskID: id(4), sequence: 1, kind: 'cancelled' })).status).toBe(200);
    const response = await stopped.post('documents/delivery-note', { ...stopped.binding, note: payload.note });
    expect(response.status).toBe(409);
    expect(await response.json()).toMatchObject({ error: 'document_receipt_unavailable' });
    expect(stopped.read()).toEqual(stopped.document);
    expect(f.network).not.toHaveBeenCalled(); expect(stopped.network).not.toHaveBeenCalled();
  });
});
