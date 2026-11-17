import { knotLive, parseKnotLiveRequest } from './knot-live';
import { dispatchKnotActor, type KnotShellEnv, type KnotShellProposal } from './knot-shell';
import { sendKnotContact } from './knot-contact';
import { knotOwnedDriverBudgetMs } from './knot-turn-economics';
import { applyKnotActivityFrame, currentKnotActivity, emptyKnotActivity, finishKnotActivity, knotActivityTimeline, startKnotActivity, type KnotActivityState } from './knot-current-activity';

type Env = KnotShellEnv & { DO: Fetcher };
type Frame = { v: number; requestID: string; sequence: number; type: string; reply?: string; proposal?: KnotShellProposal; calculation?: Record<string, unknown>; clarification?: unknown; workIncomplete?: boolean; readOnlyBrowser?: boolean; browserContinuationID?: string; [key: string]: unknown };
type Turn = {
  id: string; bot: string; conversationID: string; sourceMessageID: string; replyID: string;
  input: Record<string, unknown>; fingerprint: string; approvalEpoch: string;
  state: 'admitting' | 'queued' | 'running' | 'delivering' | 'completed' | 'degraded' | 'cancelled';
  createdAt: number; startedAt?: number; finishedAt?: number; wake: number; sequence: number;
  proposal?: KnotShellProposal; stopProposalID?: string; stopRequested?: boolean; reply?: string; clarification?: unknown; degraded?: boolean; erased?: boolean; released?: boolean;
  pushID: string; pushExpires?: number; push: 'pending' | 'sending' | 'claimed' | 'accepted' | 'suppressed' | 'unconfirmed';
  activity?: KnotActivityState;
};
const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;
const json = (value: unknown, status = 200) => Response.json(value, { status, headers: { 'Cache-Control': 'no-store' } });
const terminal = (t: Turn) => ['completed', 'degraded', 'cancelled'].includes(t.state);
const variantID = (id: string, mask: number) => (parseInt(id[0], 16) ^ mask).toString(16) + id.slice(1);
const pendingPush = (t: Turn) => ['completed', 'degraded'].includes(t.state) && ['pending', 'sending', 'claimed'].includes(t.push);
async function read(source: { body: ReadableStream<Uint8Array> | null }, limit = 256000): Promise<Record<string, unknown>> {
  const reader = source.body?.getReader(); if (!reader) throw new Error('missing_body');
  let text = '', size = 0; const decoder = new TextDecoder();
  try { for (;;) { const part = await reader.read(); if (part.done) break; size += part.value.byteLength; if (size > limit) throw new Error('oversized_body'); text += decoder.decode(part.value, { stream: true }); } }
  finally { await reader.cancel().catch(() => {}); reader.releaseLock(); }
  const value: unknown = JSON.parse(text + decoder.decode());
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('invalid_body');
  return value as Record<string, unknown>;
}
/** Existing account actor and durable alarm own execution. Reads and attachments
 * cannot start a provider, command or another copy of an admitted task. */
export class KnotOwnedTurns {
  private active = new Map<string, AbortController>();
  constructor(private ctx: DurableObjectState, private env: Env, private owner: string, private epoch: () => string) {
    ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS knot_owned_turns (id TEXT PRIMARY KEY, source TEXT UNIQUE NOT NULL, chat TEXT NOT NULL, state TEXT NOT NULL, wake REAL NOT NULL, value TEXT NOT NULL)');
    ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS knot_owned_frames (task TEXT NOT NULL, seq INTEGER NOT NULL, value TEXT NOT NULL, PRIMARY KEY(task,seq))');
    ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS knot_owned_stops (id TEXT PRIMARY KEY, created REAL NOT NULL)');
    ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS knot_owned_seen (id TEXT PRIMARY KEY)');
    ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS knot_owned_erasures (chat TEXT PRIMARY KEY)');
  }
  private get(id: string): Turn | undefined {
    const row = this.ctx.storage.sql.exec<{ value: string }>('SELECT value FROM knot_owned_turns WHERE id=?', id).toArray()[0];
    return row ? JSON.parse(row.value) as Turn : undefined;
  }
  private all(): Turn[] { return this.ctx.storage.sql.exec<{ value: string }>('SELECT value FROM knot_owned_turns ORDER BY wake,id').toArray().map(r => JSON.parse(r.value) as Turn); }
  private save(t: Turn): boolean {
    const current = this.get(t.id);
    const rank = { admitting: 0, queued: 1, running: 2, delivering: 3, completed: 4, degraded: 4, cancelled: 5 };
    if (current && (current.erased && !t.erased || current.released && !t.released || rank[current.state] > rank[t.state] || current.sequence > t.sequence)) return false;
    if (!current && this.ctx.storage.sql.exec('SELECT 1 FROM knot_owned_seen WHERE id=?', t.id).toArray().length) return false;
    this.ctx.storage.sql.exec('INSERT INTO knot_owned_turns VALUES (?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET state=excluded.state,wake=excluded.wake,value=excluded.value', t.id, t.sourceMessageID, t.conversationID, t.state, t.wake, JSON.stringify(t));
    return true;
  }
  private erased(chat: string): boolean { return this.ctx.storage.sql.exec("SELECT 1 FROM knot_owned_erasures WHERE chat IN (?,'*') LIMIT 1", chat).toArray().length > 0; }
  private valid(t: Turn): boolean { const current = this.get(t.id); return !!current && current.state === t.state && current.sequence === t.sequence && !terminal(current) && !current.erased && !this.erased(current.conversationID) && current.approvalEpoch === t.approvalEpoch && t.approvalEpoch === this.epoch(); }
  private summary(t: Turn) { return { id: t.id, bot: t.bot, conversationID: t.conversationID, sourceMessageID: t.sourceMessageID, replyID: t.replyID, state: t.state, createdAt: t.createdAt, startedAt: t.startedAt, finishedAt: t.finishedAt, sequence: t.sequence }; }
  cleanup(): void {
    const completed = this.all().filter(t => terminal(t) && !pendingPush(t) && (t.state !== 'cancelled' || t.released)).sort((a,b) => (b.finishedAt ?? b.createdAt) - (a.finishedAt ?? a.createdAt));
    for (const [i,t] of completed.entries()) if (!this.active.has(t.id) && (i >= 100 || (t.finishedAt ?? t.createdAt) < Date.now() - 86400000)) {
      // Content retention is bounded; permanent content-free identities prevent
      // old admission IDs from ever becoming a new execution grant.
      this.ctx.storage.transactionSync(() => {
        this.ctx.storage.sql.exec('INSERT OR IGNORE INTO knot_owned_seen VALUES (?)', t.id);
        this.ctx.storage.sql.exec('DELETE FROM knot_owned_frames WHERE task=?', t.id);
        this.ctx.storage.sql.exec('DELETE FROM knot_owned_turns WHERE id=?', t.id);
      });
    }
  }
  nextWake(): number[] { return this.all().filter(t => !terminal(t) || pendingPush(t) || t.state === 'cancelled' && !t.released).map(t => this.active.has(t.id) ? Date.now() + 30000 : t.wake); }
  private history(path: string, body: unknown): Promise<Response> {
    return this.env.DO.fetch(new Request('https://internal/internal/owned-turns/' + path, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Knot-Owner': this.owner, 'X-Rork-DO-Class': 'KnotConversationAccount', 'X-Rork-DO-Id': this.owner }, body: JSON.stringify(body), signal: AbortSignal.timeout(15000) }));
  }
  private async reserve(t: Turn): Promise<boolean> {
    const before = this.get(t.id);
    if (!before || before.erased || before.state === 'cancelled') return false;
    if (before.state !== 'admitting') return true;
    if (!this.valid(before)) { await this.cancel(before); return false; }
    const bound = await this.history('reserve', { taskID: before.id, bot: before.bot, conversationID: before.conversationID, sourceMessageID: before.id, replyID: before.replyID, text: before.input.message, createdAt: before.input.sourceCreatedAt });
    const ok = bound.ok, denied = [400,409,410,507].includes(bound.status); await bound.body?.cancel();
    // Another submit/alarm may have finished admission while reservation awaited.
    // Never requeue it or use a stale denial to cancel stronger delivery state.
    const current = this.get(t.id);
    if (!current || current.erased || current.state === 'cancelled') return false;
    if (current.state !== 'admitting') return true;
    if (!ok) { if (denied) await this.cancel(current); else throw new Error('history_unavailable'); return false; }
    if (!this.valid(current)) { await this.cancel(current); return false; }
    current.state = 'queued'; current.wake = Date.now() + 1000; return this.save(current);
  }
  async route(request: Request): Promise<Response | null> {
    const url = new URL(request.url);
    if (url.pathname === '/internal/knot/contact-claim' && request.method === 'POST') {
      const body = await read(request.clone(), 1500), t = this.all().find(t => t.pushID === body.eventID);
      if (!t) return null;
      if (!['completed', 'degraded'].includes(t.state) || t.erased || t.push !== 'sending' || t.pushExpires !== body.expires || t.pushExpires! <= Date.now()) return json({ error: 'event_unavailable' }, 409);
      t.push = 'claimed'; this.save(t);
      return json({ owner: this.owner, eventID: t.pushID, channel: 'completion', bot: t.bot, conversationID: t.conversationID, expiresAt: t.pushExpires });
    }
    if (url.pathname === '/internal/owned-turns/erase' && request.method === 'POST') {
      const body = await read(request, 1000);
      if (typeof body.conversationID !== 'string' || !uuid.test(body.conversationID)) return json({ error: 'invalid_context' }, 400);
      await this.cancelAll(body.conversationID, true); return json({ ok: true });
    }
    if (!url.pathname.startsWith('/knot/turns')) return null;
    if (url.pathname === '/knot/turns' && request.method === 'GET') return json({ tasks: this.all().filter(t => !t.erased).sort((a,b) => b.createdAt-a.createdAt).slice(0,100).map(t => this.summary(t)), approvalEpoch: this.epoch() });
    if (url.pathname === '/knot/turns' && request.method === 'POST') {
      const input = await read(request), parsed = parseKnotLiveRequest(input);
      if (!parsed || parsed.sharedConversation || !parsed.foregroundTurn || parsed.shellResultID || parsed.browserContinuationID || !parsed.conversationID || !parsed.sourceMessageID || parsed.requestID.toLowerCase() !== parsed.sourceMessageID) return json({ error: 'invalid_owned_turn' }, 400);
      const id = parsed.sourceMessageID;
      const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify([parsed.bot, parsed.conversationID, parsed.message])));
      const fingerprint = Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2,'0')).join('');
      const t: Turn = { id, bot: parsed.bot, conversationID: parsed.conversationID, sourceMessageID: id, replyID: variantID(id,8), input: { ...input, requestID: id }, fingerprint, approvalEpoch: String(input.backgroundApprovalEpoch), state: 'admitting', createdAt: Date.now(), wake: Date.now() + 30000, sequence: 0, pushID: crypto.randomUUID(), push: 'pending' };
      // Durable admission intent precedes cross-actor reservation. A crash in
      // that gap is recoverable without a leaked reservation or model replay.
      const existing = await this.ctx.storage.transaction(async txn => {
        if (this.erased(t.conversationID)) return json({ error: 'conversation_deleted' }, 410);
        const old = this.get(id);
        if (old) return !old.erased && old.fingerprint === fingerprint ? json({ task: this.summary(old) }) : json({ error: 'source_conflict' }, 409);
        if (this.ctx.storage.sql.exec('SELECT 1 FROM knot_owned_seen WHERE id=?', id).toArray().length) return json({ error: 'task_retired' }, 410);
        if (this.ctx.storage.sql.exec('SELECT 1 FROM knot_owned_stops WHERE id=?', id).toArray().length || t.approvalEpoch !== this.epoch()) return json({ error: 'permission_changed' }, 409);
        if (this.all().filter(t => !terminal(t)).length >= 8) return json({ error: 'task_capacity' }, 409);
        this.save(t); await txn.setAlarm(Math.min(await txn.getAlarm() ?? Infinity, t.wake));
        return null;
      });
      if (existing) return existing;
      if (await this.reserve(t)) return json({ task: this.summary(this.get(id) ?? t) }, 202);
      return json({ error: 'source_unavailable' }, 409);
    }
    const match = /^\/knot\/turns\/([0-9a-f-]{36})(?:\/(cancel))?$/.exec(url.pathname);
    if (!match || !uuid.test(match[1])) return json({ error: 'not_found' }, 404);
    if (request.method === 'POST' && match[2] === 'cancel') {
      this.ctx.storage.sql.exec('INSERT OR IGNORE INTO knot_owned_stops VALUES (?,?)', match[1], Date.now());
      const t = this.get(match[1]); if (t) await this.cancel(t);
      return json({ ok: true });
    }
    const t = this.get(match[1]); if (!t || t.erased) return json({ error: 'not_found' }, 404);
    if (request.method !== 'GET' || match[2]) return json({ error: 'not_found' }, 404);
    const after = Number(url.searchParams.get('after') ?? 0);
    if (!Number.isSafeInteger(after) || after < 0 || after > t.sequence) return json({ error: 'invalid_cursor' }, 400);
    const rows = this.ctx.storage.sql.exec<{ seq: number; value: string }>('SELECT seq,value FROM knot_owned_frames WHERE task=? AND seq>? ORDER BY seq LIMIT 65', t.id, after).toArray();
    const page: typeof rows = []; let size = 0;
    for (const row of rows.slice(0,64)) { if (page.length && size + row.value.length > 180000) break; page.push(row); size += row.value.length; }
    const next = page.at(-1)?.seq ?? after;
    // The pill is server state: present only while real work is open (or was
    // just shown), null once the turn is terminal.
    return json({ task: this.summary(t), events: page.map(r => JSON.parse(r.value)), next, hasMore: next < t.sequence, terminal: terminal(t), currentActivity: currentKnotActivity(t.activity, t.id, terminal(t)), activityTimeline: knotActivityTimeline(t.activity), ...(terminal(t) && typeof t.reply === 'string' ? { result: { reply: t.reply, clarification: t.clarification } } : {}) });
  }
  private frame(t: Turn, frame: Frame) {
    if (!this.valid(t)) throw new Error('task_closed');
    if (frame.requestID.toLowerCase() !== t.id || frame.sequence !== t.sequence + 1 || JSON.stringify(frame).length > 300000) throw new Error('invalid_owned_frame');
    const usage = this.ctx.storage.sql.exec<{ bytes: number }>('SELECT COALESCE(SUM(LENGTH(value)),0) AS bytes FROM knot_owned_frames WHERE task=?', t.id).one().bytes;
    if (usage > 1800000 || frame.sequence > 4000) throw new Error('owned_event_capacity');
    t.sequence = frame.sequence;
    if (frame.currentActivity) applyKnotActivityFrame(t.activity ??= emptyKnotActivity(), frame.currentActivity);
    this.ctx.storage.sql.exec('INSERT INTO knot_owned_frames VALUES (?,?,?)', t.id, frame.sequence, JSON.stringify(frame));
    t.wake = Date.now() + 30000; this.save(t);
  }
  private async event(t: Turn, kind: string, detail?: { reason: string; status?: number; commandDispatched?: boolean }) {
    const current = this.get(t.id);
    if (!current || current.erased || this.erased(current.conversationID) || current.state === 'cancelled' && kind !== 'background_stopped') return;
    const sequence = kind === 'tool_request_rejected' ? (detail?.reason === 'workspace_termination_unconfirmed' ? 7 : 6) : ['background_started','background_completed','background_degraded','background_stopped','background_push_unconfirmed'].indexOf(kind) + 1;
    // Separate lifecycle request identity avoids collisions with the live SSE
    // sequence and stays within the existing Events validator's 1...1000 limit.
    const response = await dispatchKnotActor(this.env, this.owner, 'activity', { bot: t.bot, conversationID: t.conversationID, requestID: variantID(t.id,4), taskID: t.id, sourceMessageID: t.sourceMessageID, sequence, kind, detail }, AbortSignal.timeout(10000));
    if (!response.ok) { await response.body?.cancel(); throw new Error('task_event_unavailable'); }
    await response.body?.cancel();
  }
  async cancelAll(conversationID?: string, erase = false): Promise<void> {
    // Seal admission before enumeration: a delayed/new POST cannot slip between
    // this actor's erasure and the separate history actor's deletion.
    if (erase) this.ctx.storage.sql.exec('INSERT OR IGNORE INTO knot_owned_erasures VALUES (?)', conversationID ?? '*');
    // Invalidate every matching object synchronously before awaiting receipts.
    const targets = this.all().filter(t => !conversationID || t.conversationID === conversationID);
    for (const t of targets) {
      if (!terminal(t) || erase) {
        t.state = 'cancelled'; t.finishedAt = Date.now(); t.push = 'suppressed'; t.wake = Date.now() + 1000;
        this.active.get(t.id)?.abort();
        t.stopProposalID ??= t.proposal?.id; t.proposal = undefined;
        if (erase) { this.ctx.storage.sql.exec('DELETE FROM knot_owned_frames WHERE task=?', t.id); t.erased = true; t.input = {}; t.reply = undefined; t.clarification = undefined; }
        this.save(t);
      }
    }
    for (const t of targets) if (t.state === 'cancelled') await this.release(t);
  }
  private async cancel(t: Turn) {
    const current = this.get(t.id); if (!current || terminal(current) && current.state !== 'cancelled') return;
    t = current;
    t.state = 'cancelled'; t.finishedAt ??= Date.now(); t.push = 'suppressed'; t.wake = Date.now() + 1000;
    t.stopProposalID ??= t.proposal?.id; t.proposal = undefined; this.save(t);
    this.active.get(t.id)?.abort();
    await this.release(t);
  }
  private async release(t: Turn) {
    const latest = this.get(t.id); if (!latest || latest.released || latest.state !== 'cancelled') return;
    t = latest;
    const r = await this.history('release', { taskID: t.id, bot: t.bot, conversationID: t.conversationID });
    const ok = r.ok || r.status === 410; await r.body?.cancel(); if (!ok) throw new Error('release_unavailable');
    const stopProposalID = this.get(t.id)?.stopProposalID ?? t.stopProposalID ?? t.proposal?.id;
    if (stopProposalID) { const r = await dispatchKnotActor(this.env, this.owner, 'cancel', { proposalID: stopProposalID, bot: t.bot, conversationID: t.conversationID }, AbortSignal.timeout(10000)); const ok = r.ok || r.status === 404; await r.body?.cancel(); if (!ok) throw new Error('stop_unconfirmed'); }
    if (!t.erased) await this.event(t, 'background_stopped');
    const current = this.get(t.id); if (!current) return;
    current.released = true; current.input = {}; current.proposal = undefined; current.stopProposalID = undefined; this.save(current);
  }
  /** Called only by the account alarm; never by submit, GET or attachment. */
  async tick(): Promise<void> {
    const due = this.all().filter(t => (!terminal(t) || pendingPush(t) || t.state === 'cancelled' && !t.released) && !this.active.has(t.id) && t.wake <= Date.now());
    const t = due[0]; if (!t) return;
    const controller = new AbortController(); this.active.set(t.id, controller);
    // Do not undercut the admitted 14-minute file task at 13 minutes. Keep
    // settlement headroom before the platform's 15-minute alarm boundary.
    const deadline = setTimeout(() => controller.abort(), knotOwnedDriverBudgetMs);
    try {
      await this.ctx.storage.setAlarm(Date.now() + 30000);
      if (t.state === 'cancelled') { await this.release(t); return; }
      if (pendingPush(t)) { await this.push(t); return; }
      if (!this.valid(t)) { await this.cancel(t); return; }
      if (t.state === 'admitting') { await this.reserve(t); return; }
      if (t.state === 'delivering') { await this.deliver(t); return; }
      if (t.state === 'running') {
        // Lost orchestration observes persisted receipts only. It never repeats
        // the initial provider call or an uncertain browser/shell side effect.
        await this.finish(t, t.reply, true); return;
      }
      const account = await fetch('https://uryyyegnbtlmyhqlgndy.supabase.co/auth/v1/admin/users/' + this.owner, { headers: { apikey: this.env.SUPABASE_SERVICE_ROLE_KEY ?? '', Authorization: 'Bearer ' + (this.env.SUPABASE_SERVICE_ROLE_KEY ?? '') }, signal: AbortSignal.timeout(5000), redirect: 'manual' });
      if (!account.ok) { await account.body?.cancel(); if ([404,410].includes(account.status)) { await this.cancel(t); return; } throw new Error('account_unavailable'); }
      const identity = await read(account, 100000);
      if (identity.id !== this.owner || typeof identity.banned_until === 'string' && Date.parse(identity.banned_until) > Date.now()) { await this.cancel(t); return; }
      if (!this.valid(t) || controller.signal.aborted) return;
      t.state = 'running'; t.startedAt = Date.now(); t.wake = Date.now() + 30000; t.activity = startKnotActivity(t.activity ?? emptyKnotActivity()); this.save(t);
      await this.event(t, 'background_started');
      if (!this.valid(t)) return;
      const response = await knotLive(new Request('https://internal/knot/chat/stream', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(t.input), signal: controller.signal }), this.env, this.owner, this.ctx);
      if (!response.ok || !response.body) { await response.body?.cancel(); await this.finish(t, undefined, true); return; }
      const reader = response.body.getReader(), decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }); let buffer = '', complete: Frame | undefined;
      // Do not wait indefinitely for the producer's asynchronous cleanup to close
      // its stream after the owned deadline or an explicit Stop.
      const detach = () => { void reader.cancel().catch(() => {}); };
      controller.signal.addEventListener('abort', detach, { once: true });
      if (controller.signal.aborted) detach();
      try {
        for (;;) {
          const part = await reader.read(); if (part.done) break;
          if (!this.valid(t)) return;
          if (controller.signal.aborted) throw new Error('owned_driver_deadline');
          buffer += decoder.decode(part.value, { stream: true });
          if (buffer.length > 400000) throw new Error('oversized_frame');
          let boundary: number;
          while ((boundary = buffer.indexOf('\n\n')) >= 0) {
            const raw = buffer.slice(0,boundary); buffer = buffer.slice(boundary + 2);
            if (!raw.startsWith('data: ')) continue;
            const frame = JSON.parse(raw.slice(6)) as Frame;
            this.frame(t, frame);
            if (frame.type === 'shell_proposal') {
              const p = frame.proposal;
              if (!p || p.taskID !== t.id || p.sourceMessageID !== t.sourceMessageID || p.bot !== t.bot || p.conversationID !== t.conversationID) throw new Error('proposal_owner_mismatch');
              t.proposal = p; t.stopProposalID = p.id; t.stopRequested = false; this.save(t);
              const executed = await dispatchKnotActor(this.env, this.owner, 'execute', { proposalID: p.id, bot: t.bot, conversationID: t.conversationID, command: p.command, timeoutMs: p.timeoutMs, executionVersion: 'knot_shell_automatic_v1' }, controller.signal);
              if (!executed.ok) {
                const rejection = await read(executed, 4096);
                const reason = ['workspace_busy_or_uncertain', 'exact_command_expired_or_mismatched', 'exact_command_expired', 'live_session_capability_unavailable'].includes(String(rejection.error)) ? String(rejection.error) : 'execution_unavailable';
                await this.event(t, 'tool_request_rejected', { reason, status: executed.status, commandDispatched: rejection.dispatchAccepted === false ? false : undefined });
                throw new Error(reason);
              }
              await executed.body?.cancel();
            }
            if (!this.valid(t)) return;
            if (frame.type === 'calculation_receipt' && frame.calculation) {
              const saved = await this.history('calculation', { taskID: t.id, conversationID: t.conversationID, bot: t.bot, calculation: frame.calculation });
              if (!saved.ok) { await saved.body?.cancel(); throw new Error('calculation_delivery_unavailable'); } await saved.body?.cancel();
            }
            if (frame.type === 'complete') complete = frame;
          }
        }
      } finally { controller.signal.removeEventListener('abort', detach); await reader.cancel().catch(() => {}); reader.releaseLock(); }
      if (!this.valid(t)) return;
      if (controller.signal.aborted) throw new Error('owned_driver_deadline');
      buffer += decoder.decode();
      if (buffer.trim()) throw new Error('owned_stream_incomplete');
      t.clarification = complete?.clarification;
      let reply = complete?.reply;
      if (complete?.readOnlyBrowser && reply) reply = 'Browser findings:\n\n' + reply.replaceAll('`', '’') + (complete.browserContinuationID ? '\n\nThis review is partial. Ask me to continue for the remaining pages; no uncertain input has been repeated.' : '');
      await this.finish(t, reply, !complete || complete.workIncomplete === true || !!complete.browserContinuationID, complete?.reply === '');
    } catch {
      controller.abort();
      const current = this.get(t.id);
      if (current) {
        // Persisted delivery, cancellation and push outboxes are retried; no
        // catch path may replace their stronger state with stale task content.
        if (terminal(current) || current.state === 'delivering' || current.state === 'admitting') { current.wake = Date.now() + 15000; this.save(current); }
        else {
          try { await this.finish(current, undefined, true); }
          catch { const pending = this.get(t.id); if (pending) { pending.wake = Date.now() + 15000; this.save(pending); } }
        }
      }
    } finally { clearTimeout(deadline); controller.abort(); this.active.delete(t.id); }
  }
  private async finish(t: Turn, reply: string | undefined, degraded: boolean, explicitSilentComplete = false) {
    if (!this.valid(t)) return;
    let captured = false;
    try {
      const response = await dispatchKnotActor(this.env, this.owner, 'documents', { action: 'list', bot: t.bot, conversationID: t.conversationID }, AbortSignal.timeout(10000));
      if (response.ok) { const body = await read(response, 1000000); captured = Array.isArray(body.documents) && body.documents.some((d: { sourceMessageID?: string }) => d.sourceMessageID === t.sourceMessageID); }
      else await response.body?.cancel();
    } catch { /* Unavailable capture evidence can never certify silent success. */ }
    if (!this.valid(t)) return;
    // Only a clean explicit completion plus this source's authenticated capture
    // permits silence. A file must never upgrade failed/lost/interrupted work.
    if (!reply?.trim() && !(explicitSilentComplete && captured)) degraded = true;
    // A lost or timed-out orchestrator cannot declare a still-running command
    // finished. Observe receipts, send at most one stop intent, then observe only.
    let unconfirmed = false;
    if (degraded && t.proposal) {
      let settled = false;
      try {
        const status = await dispatchKnotActor(this.env, this.owner, 'status', { proposalID: t.proposal.id, bot: t.bot, conversationID: t.conversationID }, AbortSignal.timeout(10000));
        if (status.ok) settled = (await read(status)).terminationConfirmed === true;
        else await status.body?.cancel();
        if (!this.valid(t)) return;
        if (!settled && !t.stopRequested) {
          t.stopRequested = true; this.save(t); // Persist intent before I/O; no ambiguous repeat.
          const stopped = await dispatchKnotActor(this.env, this.owner, 'cancel', { proposalID: t.proposal.id, bot: t.bot, conversationID: t.conversationID }, AbortSignal.timeout(10000));
          if (stopped.ok) settled = (await read(stopped)).terminationConfirmed === true;
          else await stopped.body?.cancel();
        }
      } catch { /* Retain uncertainty, never infer termination from a timeout. */ }
      if (!this.valid(t)) return;
      if (!settled && Date.now() < (t.startedAt ?? t.createdAt) + 960000) {
        t.reply = reply; t.degraded = true; t.wake = Date.now() + 5000; this.save(t); return;
      }
      unconfirmed = !settled;
    }
    if (reply && (reply.length > 64000 || new TextEncoder().encode(reply).length > 85000)) { reply = undefined; degraded = true; t.clarification = undefined; }
    // No authored result means no bubble. This explicit terminal acknowledgment
    // is durable and source-bound, not a manufactured failure/success message.
    t.reply = reply?.trim() ? reply : '';
    if (unconfirmed) await this.event(t, 'tool_request_rejected', { reason: 'workspace_termination_unconfirmed' });
    if (!t.reply && !captured) t.push = 'suppressed';
    t.degraded = degraded; t.state = 'delivering'; t.finishedAt = Date.now(); t.wake = Date.now() + 15000;
    // Keep the authored waiting operation open through durable delivery.
    // The task is not finished merely because answer generation returned.
    if (this.save(t)) await this.deliver(t);
  }
  private async deliver(t: Turn) {
    if (!this.valid(t)) return;
    const saved = await this.history('deliver', { taskID: t.id, conversationID: t.conversationID, bot: t.bot, replyID: t.replyID, text: t.reply, ...(t.reply === '' ? { silent: true } : {}), createdAt: t.finishedAt, clarification: t.reply === '' ? undefined : t.clarification });
    const status = saved.status; await saved.body?.cancel();
    if (status === 410) { await this.cancel(t); return; }
    if (!saved.ok) throw new Error('delivery_unavailable');
    if (!this.valid(t)) return;
    await this.event(t, t.degraded ? 'background_degraded' : 'background_completed');
    if (!this.valid(t)) return;
    t.state = t.degraded ? 'degraded' : 'completed'; t.input = {}; t.proposal = undefined; t.stopProposalID = undefined; t.wake = Date.now() + 1000;
    if (t.activity) finishKnotActivity(t.activity);
    if (!this.save(t)) return;
    await this.ctx.storage.setAlarm(Date.now() + 1000);
    await this.push(t);
  }
  private async push(t: Turn) {
    const current = this.get(t.id); if (!current || !pendingPush(current) || current.erased) return;
    if (current.push !== 'pending') {
      current.push = 'unconfirmed'; this.save(current); await this.event(current, 'background_push_unconfirmed'); return;
    }
    // Intent is durable before I/O. A crash after this point cannot cause a
    // second alert; recovery records uncertainty instead of sending again.
    current.push = 'sending'; current.pushExpires = Date.now() + 600000; current.wake = Date.now() + 30000; this.save(current);
    await this.ctx.storage.setAlarm(current.wake);
    try {
      const outcome = await sendKnotContact(this.env, this.owner, current.pushID, current.pushExpires);
      const latest = this.get(t.id); if (latest && !latest.erased && latest.state !== 'cancelled') { latest.push = outcome; this.save(latest); }
    } catch {
      const latest = this.get(t.id); if (latest && !latest.erased && latest.state !== 'cancelled') { latest.push = 'unconfirmed'; this.save(latest); await this.event(latest, 'background_push_unconfirmed'); }
    }
  }
}

export function knotOwnedTurnsRoute(request: Request, env: Env, userID: string): Promise<Response> {
  const owner = userID.toLowerCase();
  return env.DO.fetch(new Request(new Request(request.url, request), { headers: { 'Content-Type': 'application/json', 'X-Knot-Owner': owner, 'X-Rork-DO-Class': 'KnotBackgroundAccount', 'X-Rork-DO-Id': owner } }));
}
