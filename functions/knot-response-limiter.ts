import { DurableObject } from 'cloudflare:workers';

/** A hashed account bucket. Stores counters and expiring call IDs only,
 * never questions, answers, prompts, audio or transcripts. */
export class KnotResponseLimiter extends DurableObject {
  constructor(ctx: DurableObjectState, env: Record<string, unknown>) {
    super(ctx, env);
    this.ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS counter (id INTEGER PRIMARY KEY, started REAL NOT NULL, count INTEGER NOT NULL)');
    this.ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS voice_lease (id TEXT PRIMARY KEY, expires REAL NOT NULL)');
  }

  override async fetch(request: Request): Promise<Response> {
    if (request.method !== 'POST') return new Response(null, { status: 405 });
    const now = Date.now();
    const path = new URL(request.url).pathname;
    if (path.startsWith('/voice-lease/')) {
      this.ctx.storage.sql.exec('DELETE FROM voice_lease WHERE expires <= ?', now);
      if (Number(request.headers.get('Content-Length') ?? 0) > 500) return new Response(null, { status: 400 });
      const input = await request.json() as { id?: unknown; expires?: unknown };
      if (typeof input.id !== 'string' || !/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(input.id)) return new Response(null, { status: 400 });
      if (path === '/voice-lease/end') {
        this.ctx.storage.sql.exec('DELETE FROM voice_lease WHERE id = ?', input.id);
        return new Response(null, { status: 204 });
      }
      if (path === '/voice-lease/check') {
        const active = this.ctx.storage.sql.exec('SELECT id FROM voice_lease WHERE id = ? AND expires > ?', input.id, now).toArray().length === 1;
        return new Response(null, { status: active ? 204 : 403 });
      }
      if (path !== '/voice-lease/open' || typeof input.expires !== 'number' || input.expires <= now || input.expires > now + 1200000) return new Response(null, { status: 400 });
      if (this.ctx.storage.sql.exec('SELECT id FROM voice_lease LIMIT 20').toArray().length >= 20) return new Response(null, { status: 429 });
      this.ctx.storage.sql.exec('INSERT INTO voice_lease VALUES (?, ?)', input.id, input.expires);
      return new Response(null, { status: 204 });
    }
    const row = this.ctx.storage.sql.exec<{ started: number; count: number }>('SELECT started, count FROM counter WHERE id = 1').toArray()[0];
    if (!row || now - row.started >= 300000) {
      this.ctx.storage.sql.exec('INSERT OR REPLACE INTO counter VALUES (1, ?, 1)', now);
      return new Response(null, { status: 204 });
    }
    const limit = new URL(request.url).pathname === '/voice-admit' ? 4 : 30;
    if (row.count >= limit) return new Response(null, { status: 429 });
    this.ctx.storage.sql.exec('UPDATE counter SET count = count + 1 WHERE id = 1');
    return new Response(null, { status: 204 });
  }
}
