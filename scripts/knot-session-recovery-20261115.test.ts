import { describe, expect, test, mock } from 'bun:test';

// Synthetic in-process boundary tests only. No auth, network, shell or live user.
mock.module('cloudflare:workers', () => ({ DurableObject: class {} }));
const { KnotShellConversation } = await import('../functions/knot-shell');
const { SidecarHTTPError, isUnknownSessionResponse } = await import('../functions/knot-shell-discovery');
const oldID = '11111111-1111-4111-8111-111111111111';
const newID = '22222222-2222-4222-8222-222222222222';
const owner = 'synthetic-session-recovery-only';
const log = (session_id: string) => ({ session_id, stdout: '', stderr: '', stdout_from: 0, stdout_len: 0, stderr_from: 0, stderr_len: 0, truncated: false });
function harness(failures: Error[] = []) {
  const record: any = { proposal: { id: 'test' }, workspace: owner, phase: 'creating', cancelled: false };
  const calls: { path: string; method: string; body?: unknown }[] = [], sql: string[] = [];
  const actor: any = Object.create(KnotShellConversation.prototype);
  actor.get = () => record; actor.save = () => {}; actor.event = () => {};
  actor.ctx = { storage: { sql: { exec: (query: string) => { sql.push(query); return { toArray: () => query.startsWith('SELECT') ? [{ session_id: oldID }] : [] }; } } } };
  let opens = 0;
  actor.provider = async (path: string, method = 'GET', body?: unknown) => {
    calls.push({ path, method, body });
    if (path === '/sessions') { opens++; return { attached: opens === 1, session_id: opens === 1 ? oldID : newID, user_id: owner }; }
    if (failures.length) throw failures.shift();
    return log(opens === 1 ? oldID : newID);
  };
  return { actor, record, calls, sql, run: () => actor.openSessionBeforeInput('test', new AbortController().signal) };
}
describe('exact stale session recovery boundary', () => {
  test('only exact bounded unknown-session 404 payloads qualify', () => {
    for (const body of ['unknown session', '"unknown session"', '{"error":"unknown session"}', '{"detail":"unknown session"}']) expect(isUnknownSessionResponse(404, body)).toBe(true);
    for (const [status, body] of [[400, 'unknown session'], [500, 'unknown session'], [404, 'Not found'], [404, '{"error":"unknown session; retry input"}'], [404, '{"error":{"message":"unknown session"}}']] as const) expect(isUnknownSessionResponse(status, body)).toBe(false);
  });
  test('confirmed missing pre-input handle reattaches same owner and main once', async () => {
    const h = harness([new SidecarHTTPError(404, true)]); await h.run();
    expect(h.calls.map(x => x.method + ' ' + x.path)).toEqual(['POST /sessions', `GET /sessions/${oldID}/log?offset=0`, 'POST /sessions', `GET /sessions/${newID}/log?offset=0`]);
    expect(h.calls.filter(x => x.path === '/sessions').map(x => x.body)).toEqual([{ user_id: owner, name: 'main' }, { user_id: owner, name: 'main' }]);
    expect(h.sql.some(x => x.startsWith('DELETE FROM session_skills'))).toBe(true);
    expect(h.sql.some(x => x.startsWith('DELETE FROM reaction_guides'))).toBe(true);
    expect(h.record.sessionID).toBe(newID);
    expect(h.record.submittedInput).toBeUndefined();
  });
  test('generic 404 and timeout do not reopen', async () => {
    for (const error of [new SidecarHTTPError(404), new Error('timeout')]) {
      const h = harness([error]); await expect(h.run()).rejects.toThrow();
      expect(h.calls.filter(x => x.path === '/sessions')).toHaveLength(1);
    }
  });
  test('second exact rejection never causes a third open', async () => {
    const h = harness([new SidecarHTTPError(404, true), new SidecarHTTPError(404, true)]);
    await expect(h.run()).rejects.toThrow(); expect(h.calls.filter(x => x.path === '/sessions')).toHaveLength(2);
  });
  test('input intent, startup guide, cancellation and uncertain state cannot replay', async () => {
    for (const patch of [{ submittedInput: 'DO NOT REPLAY' }, { boundary: {} }, { startupGuideID: 'existing-guide' }, { cancelled: true }, { phase: 'uncertain' }]) {
      const h = harness(); Object.assign(h.record, patch); await expect(h.run()).rejects.toThrow(); expect(h.calls).toHaveLength(0);
    }
  });
  test('Stop arriving during a failed read prevents reattachment', async () => {
    const h = harness(); const provider = h.actor.provider;
    h.actor.provider = async (...args: any[]) => { if (args[0].includes('/log?')) { h.record.cancelled = true; throw new SidecarHTTPError(404, true); } return provider(...args); };
    await expect(h.run()).rejects.toThrow(); expect(h.calls.filter(x => x.path === '/sessions')).toHaveLength(1);
  });
  test('a previously unknown attached session is never adopted', async () => {
    const h = harness(); h.actor.ctx.storage.sql.exec = () => ({ toArray: () => [] });
    await expect(h.run()).rejects.toThrow('unknown_attached_session'); expect(h.calls).toHaveLength(1);
  });
});
