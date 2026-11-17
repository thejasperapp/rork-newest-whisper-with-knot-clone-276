import { DurableObject } from 'cloudflare:workers';

/** One HMAC-qualified bucket; durable counters contain no identities or credentials. */
export class WhisperLoginLimiter extends DurableObject {
  constructor(ctx: DurableObjectState, env: unknown) {
    super(ctx, env);
    this.ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS attempts (id INTEGER PRIMARY KEY, started REAL NOT NULL, count INTEGER NOT NULL)');
  }

  override async fetch(request: Request): Promise<Response> {
    if (request.method !== 'POST') return new Response(null, { status: 405 });
    const limit = request.headers.get('X-Login-Limit') === '60' ? 60 : 12;
    const now = Date.now();
    const row = this.ctx.storage.sql.exec<{ started: number; count: number }>('SELECT started, count FROM attempts WHERE id = 1').toArray()[0];
    if (!row || now - row.started >= 900000) {
      this.ctx.storage.sql.exec('INSERT OR REPLACE INTO attempts VALUES (1, ?, 1)', now);
      return new Response(null, { status: 204 });
    }
    if (row.count >= limit) return new Response(null, { status: 429 });
    this.ctx.storage.sql.exec('UPDATE attempts SET count = count + 1 WHERE id = 1');
    return new Response(null, { status: 204 });
  }
}
