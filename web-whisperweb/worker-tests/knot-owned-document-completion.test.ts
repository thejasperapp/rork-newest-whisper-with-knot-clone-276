// @vitest-environment node
// Runs the real owned driver with in-memory storage and synthetic boundaries.
// No provider, account, shell session or push service is contacted.
import { afterEach, describe, expect, it, vi } from 'vitest';
const boundaries = vi.hoisted(() => ({ live: vi.fn(), actor: vi.fn(), contact: vi.fn() }));
vi.mock('../../functions/knot-live', () => ({ knotLive: boundaries.live, parseKnotLiveRequest: vi.fn() }));
vi.mock('../../functions/knot-shell', () => ({ dispatchKnotActor: boundaries.actor }));
vi.mock('../../functions/knot-contact', () => ({ sendKnotContact: boundaries.contact }));
import { KnotOwnedTurns } from '../../functions/knot-owned-turns';
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); vi.resetAllMocks(); });
const id = (n: number) => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');
function fixture(options: { frames?: Record<string, unknown>[]; document?: boolean; foreign?: boolean; tail?: string; state?: string; invalidate?: 'epoch' | 'cancel' | 'erase'; lookupFails?: boolean } = {}) {
  let epoch = 'fresh-epoch';
  let row = { id: id(1), bot: 'main', conversationID: id(2), sourceMessageID: id(1), replyID: id(3), input: {}, fingerprint: 'fixture', approvalEpoch: epoch, state: options.state ?? 'queued', createdAt: Date.now(), wake: 0, sequence: 0, pushID: id(4), push: 'pending', proposal: { id: id(5) } } as Record<string, any>;
  const frames: Record<string, any>[] = [], deliveries: Record<string, unknown>[] = [];
  const sql = { exec(query: string, ...values: unknown[]) {
    let result: unknown[] = [];
    if (query.startsWith('CREATE TABLE')) { /* schema only */ }
    else if (query === 'SELECT value FROM knot_owned_turns ORDER BY wake,id' || query === 'SELECT value FROM knot_owned_turns WHERE id=?') result = [{ value: JSON.stringify(row) }];
    else if (query.startsWith('SELECT 1 FROM knot_owned_')) result = [];
    else if (query.startsWith('SELECT COALESCE(SUM(LENGTH(value))')) result = [{ bytes: 0 }];
    else if (query.startsWith('INSERT INTO knot_owned_turns')) row = JSON.parse(String(values[5]));
    else if (query.startsWith('INSERT INTO knot_owned_frames')) frames.push(JSON.parse(String(values[2])));
    else throw new Error('Unexpected SQL: ' + query);
    return { toArray: () => result, one: () => result[0] };
  } };
  const history = vi.fn(async (request: Request) => {
    const body = await request.json() as Record<string, unknown>;
    if (new URL(request.url).pathname.endsWith('/deliver')) deliveries.push(body);
    else if (!new URL(request.url).pathname.endsWith('/release')) throw new Error('Unexpected history call');
    return Response.json({ ok: true });
  });
  const ctx = { storage: { sql, setAlarm: vi.fn(async () => {}) } };
  const driver = new KnotOwnedTurns(ctx as never, { DO: { fetch: history } } as never, id(6), () => epoch);
  boundaries.live.mockImplementation(async () => {
    const wire = (options.frames ?? [{ type: 'complete', reply: '' }]).map(frame => 'data: ' + JSON.stringify({ v: 1, requestID: id(1), sequence: 1, ...frame }) + '\n\n').join('') + (options.tail ?? '');
    return new Response(wire);
  });
  boundaries.actor.mockImplementation(async (_env: unknown, _owner: string, action: string) => {
    if (action === 'documents') {
      if (options.invalidate === 'epoch') epoch = 'revoked-epoch';
      if (options.invalidate === 'cancel') row.state = 'cancelled';
      if (options.invalidate === 'erase') row.erased = true;
      if (options.lookupFails) throw new Error('lookup unavailable');
      return Response.json({ documents: options.document === false ? [] : [{ sourceMessageID: options.foreign ? id(9) : id(1), id: 'a'.repeat(64), sha256: 'b'.repeat(64) }] });
    }
    if (action === 'activity') return Response.json({ ok: true });
    if (action === 'status') return Response.json({ terminationConfirmed: true });
    throw new Error('Unexpected actor action: ' + action);
  });
  boundaries.contact.mockResolvedValue('suppressed');
  vi.stubGlobal('fetch', vi.fn(async () => Response.json({ id: id(6) })));
  return { driver, row: () => row, frames, deliveries };
}
describe('owned captured-card completion', () => {
  it('completes an explicit clean empty reply only with an authenticated source-bound capture', async () => {
    const f = fixture(); await f.driver.tick();
    expect(f.row().state).toBe('completed');
    expect(f.deliveries).toEqual([expect.objectContaining({ text: '', silent: true, taskID: id(1) })]);
    expect(f.frames.some(frame => frame.status === 'background_degraded')).toBe(false);
    expect(boundaries.actor.mock.calls.some(call => ['status', 'cancel'].includes(call[2]))).toBe(false);
  });
  it.each([
    { document: false }, { foreign: true }, { lookupFails: true },
    { frames: [] }, { frames: [{ type: 'complete' }] }, { frames: [{ type: 'complete', reply: ' ' }] },
    { frames: [{ type: 'complete', reply: '', workIncomplete: true }] },
    { frames: [{ type: 'complete', reply: '', browserContinuationID: id(9) }] },
    { tail: 'data: {"type":"complete"' }, { state: 'running' },
  ])('does not let a file upgrade an incomplete/uncertain turn: %j', async options => {
    const f = fixture(options); await f.driver.tick();
    expect(f.row().state).toBe('degraded');
    expect(f.deliveries).toHaveLength(1);
    expect(boundaries.actor.mock.calls.some(call => call[2] === 'status')).toBe(true);
  });
  it.each(['epoch', 'cancel', 'erase'] as const)('does not deliver after %s invalidation during the capture lookup', async invalidate => {
    const f = fixture({ invalidate }); await f.driver.tick();
    expect(f.deliveries).toEqual([]);
    expect(boundaries.contact).not.toHaveBeenCalled();
  });
  it('preserves ordinary authored text without a capture', async () => {
    const f = fixture({ document: false, frames: [{ type: 'complete', reply: 'Authored answer' }] }); await f.driver.tick();
    expect(f.row().state).toBe('completed'); expect(f.deliveries).toEqual([expect.objectContaining({ text: 'Authored answer' })]);
  });
});
