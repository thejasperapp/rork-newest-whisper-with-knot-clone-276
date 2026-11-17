import { sendKnotContact, type KnotContactEnv } from './knot-contact';
export type ContactRule = { id: string; bot: string; conversationID: string; title: string; revision: string; state: string; endsAt: number; timezone: string; quietStart: number; quietEnd: number };
type Grant = { approvalID: string; ruleRevision: string; push: boolean; calls: boolean; maxCallsPerDay: 1 };
type GrantRow = { rule_id: string; revision: string; value: string };
type Event = { id: string; rule_id: string; rule_revision: string; grant_revision: string; message_id: string; channel: string; state: string; delivery: string; created: number; expires: number; next_attempt: number; tries: number; answer_id: string | null; connected: number | null; ended: number | null; token_claimed: number };
const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const day = 86400000;
const json = (value: unknown, status = 200) => Response.json(value, { status, headers: { 'Cache-Control': 'no-store' } });
/** Contact is a separate grant, off by default. It can only reference a real
 * persisted update and the exact responsibility revision reviewed natively. */
export class KnotContactStore {
  constructor(private sql: SqlStorage, private env: KnotContactEnv, private owner: string,
    private rule: (id: string) => ContactRule | undefined, private allowed: (rule: ContactRule, at: number) => number,
    private epoch: () => string, private invalidate: () => void) {
    sql.exec('CREATE TABLE IF NOT EXISTS knot_contact_grants (rule_id TEXT PRIMARY KEY, revision TEXT NOT NULL, value TEXT NOT NULL)');
    sql.exec('CREATE TABLE IF NOT EXISTS knot_contact_limits (id INTEGER PRIMARY KEY CHECK(id=1), last_invitation REAL NOT NULL)');
    sql.exec(`CREATE TABLE IF NOT EXISTS knot_contact_events (id TEXT PRIMARY KEY, rule_id TEXT NOT NULL, rule_revision TEXT NOT NULL, grant_revision TEXT NOT NULL,
      message_id TEXT NOT NULL, channel TEXT NOT NULL, state TEXT NOT NULL, delivery TEXT NOT NULL, created REAL NOT NULL, expires REAL NOT NULL,
      next_attempt REAL NOT NULL, tries INTEGER NOT NULL DEFAULT 0, answer_id TEXT, connected REAL, ended REAL, token_claimed INTEGER NOT NULL DEFAULT 0, UNIQUE(message_id,channel))`);
  }
  private grantRow(id: string): GrantRow | undefined { return this.sql.exec<GrantRow>('SELECT * FROM knot_contact_grants WHERE rule_id = ?', id).toArray()[0]; }
  grant(rule: ContactRule): Grant | null {
    const row = this.grantRow(rule.id); if (!row) return null;
    const grant = JSON.parse(row.value) as Grant;
    return grant.ruleRevision === rule.revision && rule.state !== 'paused' && rule.endsAt > Date.now() ? grant : null;
  }
  private event(id: string): Event | undefined { return this.sql.exec<Event>('SELECT * FROM knot_contact_events WHERE id = ?', id).toArray()[0]; }
  private eligible(event: Event): ContactRule | null {
    const rule = this.rule(event.rule_id), row = this.grantRow(event.rule_id);
    if (!rule || !row || rule.revision !== event.rule_revision || row.revision !== event.grant_revision || rule.state === 'paused' || rule.endsAt <= Date.now()) return null;
    const grant = this.grant(rule);
    return grant && (event.channel === 'call' ? grant.calls : grant.push) && this.allowed(rule, Date.now()) <= Date.now() + 1000 ? rule : null;
  }
  cleanup(): void {
    const now = Date.now();
    for (const event of this.sql.exec<Event>("SELECT * FROM knot_contact_events WHERE state IN ('invited','answered') OR delivery = 'queued'").toArray()) {
      const valid = this.eligible(event);
      if (!valid || (event.state === 'invited' && event.expires <= now) || (event.state === 'answered' && (event.connected ? event.connected + 20 * 60000 : event.expires) <= now)) {
        this.sql.exec("UPDATE knot_contact_events SET state = ?, ended = ?, delivery = CASE WHEN delivery = 'queued' THEN 'cancelled' ELSE delivery END WHERE id = ?", valid && event.state === 'invited' ? 'missed' : 'ended', now, event.id);
      } else if (event.channel === 'update' && event.expires <= now) {
        this.sql.exec("UPDATE knot_contact_events SET delivery = 'expired' WHERE id = ?", event.id);
      }
    }
    this.sql.exec('DELETE FROM knot_contact_limits WHERE last_invitation <= ?', now - day);
    this.sql.exec('DELETE FROM knot_contact_events WHERE created < ?', now - 30 * day);
    this.sql.exec('DELETE FROM knot_contact_events WHERE id NOT IN (SELECT id FROM knot_contact_events ORDER BY created DESC LIMIT 400)');
    this.sql.exec('DELETE FROM knot_contact_grants WHERE rule_id NOT IN (SELECT id FROM knot_rules)');
  }
  nextWake(): number[] {
    return this.sql.exec<{ due: number }>("SELECT next_attempt AS due FROM knot_contact_events WHERE delivery = 'queued' UNION ALL SELECT CASE WHEN state = 'answered' AND connected IS NOT NULL THEN connected + 1200000 ELSE expires END AS due FROM knot_contact_events WHERE state IN ('invited','answered') UNION ALL SELECT last_invitation + 86400000 AS due FROM knot_contact_limits").toArray().map(row => row.due);
  }
  clear(ruleID?: string): void {
    if (ruleID) {
      this.sql.exec('DELETE FROM knot_contact_grants WHERE rule_id = ?', ruleID);
      this.sql.exec('DELETE FROM knot_contact_events WHERE rule_id = ?', ruleID);
    } else { this.sql.exec('DELETE FROM knot_contact_grants'); this.sql.exec('DELETE FROM knot_contact_events'); }
  }
  cancelCalls(): void {
    for (const row of this.sql.exec<GrantRow>('SELECT * FROM knot_contact_grants').toArray()) {
      const grant = JSON.parse(row.value) as Grant;
      if (!grant.calls) continue;
      grant.calls = false; grant.approvalID = crypto.randomUUID();
      this.sql.exec('UPDATE knot_contact_grants SET value = ?, revision = ? WHERE rule_id = ?', JSON.stringify(grant), crypto.randomUUID(), row.rule_id);
    }
    this.cleanup();
  }
  cancelAll(): void {
    this.sql.exec('DELETE FROM knot_contact_grants');
    this.sql.exec("UPDATE knot_contact_events SET state = CASE WHEN channel = 'call' AND state IN ('invited','answered') THEN 'ended' ELSE state END, ended = COALESCE(ended,?), delivery = CASE WHEN delivery = 'queued' THEN 'cancelled' ELSE delivery END", Date.now());
  }
  enqueue(rule: ContactRule, messageID: string): void {
    const grant = this.grant(rule), row = this.grantRow(rule.id); if (!grant || !row) return;
    const now = Date.now();
    const insert = (channel: string, lifetime: number) => this.sql.exec(`INSERT OR IGNORE INTO knot_contact_events
      (id,rule_id,rule_revision,grant_revision,message_id,channel,state,delivery,created,expires,next_attempt) VALUES (?,?,?,?,?,?,?,?,?,?,?)`,
      crypto.randomUUID(), rule.id, rule.revision, row.revision, messageID, channel, channel === 'call' ? 'invited' : 'saved', 'queued', now, Math.min(rule.endsAt, now + lifetime), now + 1000);
    // A single genuine invitation per account per 24h, never a timer that
    // automatically starts an outgoing call or captures audio.
    const recentCall = this.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM knot_contact_events WHERE channel = 'call' AND created > ?", now - day).one().n;
    // Keep the daily safety limit independent of rule deletion and the bounded
    // event ledger. It contains no goal or message and expires after 24 hours.
    const lastCall = this.sql.exec<{ last_invitation: number }>('SELECT last_invitation FROM knot_contact_limits WHERE id = 1').toArray()[0]?.last_invitation;
    if (grant.calls && !recentCall && (lastCall === undefined || lastCall <= now - day) && rule.endsAt > now + 30000) {
      insert('call', 120000);
      this.sql.exec('INSERT INTO knot_contact_limits VALUES (1,?) ON CONFLICT(id) DO UPDATE SET last_invitation=excluded.last_invitation', now);
    } else if (grant.push) insert('update', 5 * 60000);
  }
  async deliver(): Promise<void> {
    this.cleanup();
    const events = this.sql.exec<Event>("SELECT * FROM knot_contact_events WHERE delivery = 'queued' AND next_attempt <= ? ORDER BY created LIMIT 2", Date.now()).toArray();
    for (const event of events) {
      if (!this.eligible(event) || event.expires <= Date.now()) continue;
      // Persist retry scheduling BEFORE network I/O. Once the bridge claims a
      // canonical event, all ambiguous attempts remain consumed (no re-alert).
      this.sql.exec('UPDATE knot_contact_events SET tries = tries + 1, next_attempt = ? WHERE id = ?', Date.now() + 60000, event.id);
      try {
        const result = await sendKnotContact(this.env, this.owner, event.id, event.expires);
        this.sql.exec("UPDATE knot_contact_events SET delivery = ? WHERE id = ? AND delivery = 'claimed'", result === 'accepted' ? 'accepted' : 'suppressed', event.id);
      } catch {
        const current = this.event(event.id); if (!current) continue;
        if (current.delivery === 'claimed') this.sql.exec("UPDATE knot_contact_events SET delivery = 'unconfirmed' WHERE id = ?", event.id);
        else if (current.tries >= 3) this.sql.exec("UPDATE knot_contact_events SET delivery = 'failed' WHERE id = ?", event.id);
      }
    }
  }
  async route(request: Request): Promise<Response | null> {
    const url = new URL(request.url);
    if (url.pathname === '/knot/background/contact-revoke-calls' && request.method === 'POST') { this.invalidate(); this.cancelCalls(); return json({ ok: true }); }
    const grantMatch = /^\/knot\/background\/([0-9a-f-]{36})\/contact$/.exec(url.pathname);
    if (grantMatch && request.method === 'POST') {
      const text = await request.text(); if (text.length > 1800) return json({ error: 'invalid_contact' }, 400);
      const input = JSON.parse(text) as Grant & { approvalEpoch: string; consentVersion: string };
      const rule = this.rule(grantMatch[1]);
      if (!rule || rule.state !== 'active' || rule.endsAt <= Date.now() || input.ruleRevision !== rule.revision) return json({ error: 'permission_changed' }, 409);
      if (input.consentVersion !== 'knot_contact_v1' || !uuid.test(input.approvalID) || typeof input.push !== 'boolean' || typeof input.calls !== 'boolean' || input.maxCallsPerDay !== 1) return json({ error: 'invalid_contact' }, 400);
      const grant: Grant = { approvalID: input.approvalID, ruleRevision: input.ruleRevision, push: input.push, calls: input.calls, maxCallsPerDay: 1 };
      const old = this.grantRow(rule.id);
      if (old && (JSON.parse(old.value) as Grant).approvalID === grant.approvalID) return JSON.stringify(grant) === old.value ? json({ ok: true }) : json({ error: 'approval_conflict' }, 409);
      if (input.approvalEpoch !== this.epoch()) return json({ error: 'permission_changed' }, 409);
      this.invalidate();
      this.sql.exec('INSERT INTO knot_contact_grants VALUES (?,?,?) ON CONFLICT(rule_id) DO UPDATE SET revision=excluded.revision,value=excluded.value', rule.id, crypto.randomUUID(), JSON.stringify(grant));
      this.cleanup(); return json({ ok: true });
    }
    if (url.pathname === '/internal/knot/contact-claim' && request.method === 'POST') {
      const input = await request.json() as { eventID?: string; expires?: number };
      const event = this.event(input.eventID ?? '');
      if (!event || event.delivery !== 'queued' || event.expires !== input.expires || event.expires <= Date.now()) return json({ error: 'event_unavailable' }, 409);
      const rule = this.eligible(event); if (!rule || (event.channel === 'call' && event.state !== 'invited')) return json({ error: 'permission_changed' }, 409);
      const message = this.sql.exec<{ id: string }>('SELECT id FROM knot_messages WHERE id = ? AND rule_id = ?', event.message_id, rule.id).toArray()[0];
      if (!message) return json({ error: 'message_unavailable' }, 409);
      this.sql.exec("UPDATE knot_contact_events SET delivery = 'claimed' WHERE id = ?", event.id);
      return json({ owner: this.owner, eventID: event.id, channel: event.channel, bot: rule.bot, conversationID: rule.conversationID, expiresAt: event.expires });
    }
    if (url.pathname === '/internal/knot/voice-claim' && request.method === 'POST') {
      const input = await request.json() as { invitationID?: string; answerID?: string; bot?: string };
      const event = this.event(input.invitationID ?? '');
      if (!event || event.channel !== 'call' || event.state !== 'answered' || event.expires <= Date.now() || event.answer_id !== input.answerID || event.token_claimed) return json({ error: 'invitation_unavailable' }, 409);
      const rule = this.eligible(event); if (!rule || rule.bot !== input.bot) return json({ error: 'permission_changed' }, 409);
      const message = this.sql.exec<{ text: string }>('SELECT text FROM knot_messages WHERE id = ? AND rule_id = ?', event.message_id, rule.id).toArray()[0];
      if (!message) return json({ error: 'message_unavailable' }, 409);
      this.sql.exec('UPDATE knot_contact_events SET token_claimed = 1 WHERE id = ?', event.id);
      return json({ title: rule.title, text: message.text });
    }
    if (url.pathname === '/knot/background/invitations' && request.method === 'GET') {
      return json({ invitations: this.sql.exec<Event>("SELECT * FROM knot_contact_events WHERE channel = 'call' ORDER BY created DESC LIMIT 40").toArray().map(event => this.summary(event)).filter(Boolean) });
    }
    const match = /^\/knot\/background\/invitations\/([0-9a-f-]{36})(?:\/(answer|decline|connected|end))?$/.exec(url.pathname);
    if (!match) return null;
    const event = this.event(match[1]); if (!event || event.channel !== 'call') return json({ error: 'not_found' }, 404);
    if (request.method === 'GET' && !match[2]) return json({ invitation: this.summary(event) });
    if (request.method !== 'POST' || !match[2]) return json({ error: 'not_found' }, 404);
    const text = await request.text(); if (text.length > 600) return json({ error: 'invalid_request' }, 400);
    const input = JSON.parse(text || '{}') as { answerID?: string };
    if (match[2] === 'answer') {
      if (!uuid.test(input.answerID ?? '') || !this.eligible(event) || event.expires <= Date.now()) return json({ error: 'invitation_expired' }, 409);
      if (event.state === 'answered' && event.answer_id === input.answerID) return json({ invitation: this.summary(event) });
      if (event.state !== 'invited') return json({ error: 'invitation_unavailable' }, 409);
      const rule = this.eligible(event)!;
      this.sql.exec("UPDATE knot_contact_events SET state = 'answered', answer_id = ?, expires = ?, delivery = CASE WHEN delivery = 'queued' THEN 'cancelled' ELSE delivery END WHERE id = ?", input.answerID!, Math.min(rule.endsAt, Date.now() + 45000), event.id);
    } else if (match[2] === 'decline') {
      if (event.state !== 'invited') return json({ error: 'invitation_unavailable' }, 409);
      this.sql.exec("UPDATE knot_contact_events SET state = 'declined', ended = ?, delivery = CASE WHEN delivery = 'queued' THEN 'cancelled' ELSE delivery END WHERE id = ?", Date.now(), event.id);
    } else {
      if (event.state !== 'answered' || event.answer_id !== input.answerID) return json({ error: 'invitation_unavailable' }, 409);
      if (match[2] === 'connected') {
        if (!this.eligible(event) || !event.token_claimed || event.expires <= Date.now()) return json({ error: 'invitation_expired' }, 409);
        this.sql.exec('UPDATE knot_contact_events SET connected = COALESCE(connected,?) WHERE id = ?', Date.now(), event.id);
      } else this.sql.exec("UPDATE knot_contact_events SET state = 'ended', ended = ? WHERE id = ?", Date.now(), event.id);
    }
    return json({ invitation: this.summary(this.event(event.id)!) });
  }
  private summary(event: Event): unknown {
    const rule = this.rule(event.rule_id); if (!rule) return null;
    return { id: event.id, ruleID: rule.id, bot: rule.bot, conversationID: rule.conversationID, title: rule.title,
      state: event.state, createdAt: event.created, expiresAt: event.expires, connectedAt: event.connected, endedAt: event.ended, delivery: event.delivery };
  }
}
