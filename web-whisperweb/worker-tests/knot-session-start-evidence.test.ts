// @vitest-environment node
// Synthetic actor boundary only. No live provider, auth or shell operations.
import { describe, expect, it, vi } from 'vitest';
vi.mock('cloudflare:workers', () => ({ DurableObject: class {} }));
import { KnotShellConversation } from '../../functions/knot-shell';
import { SidecarHTTPError } from '../../functions/knot-shell-discovery';
const knownID = '11111111-1111-4111-8111-111111111111';
const returnedID = '22222222-2222-4222-8222-222222222222';
const workspace = 'synthetic-session-evidence-only';
function harness(known: boolean, owner = workspace) {
  const record = { proposal: { id: 'synthetic' }, workspace, phase: 'creating', cancelled: false } as Record<string, any>;
  const actor = Object.create(KnotShellConversation.prototype) as any;
  actor.get = () => record; actor.save = vi.fn(); actor.event = vi.fn(); actor.stamp = vi.fn();
  actor.ctx = { storage: { sql: { exec: () => ({ toArray: () => known ? [{ session_id: returnedID }] : [{ session_id: knownID }] }) } } };
  actor.provider = vi.fn(async (path: string) => path === '/sessions' ? { user_id: owner, attached: true, session_id: returnedID } : { session_id: returnedID, stdout: '', stderr: '', stdout_from: 0, stdout_len: 0, stderr_from: 0, stderr_len: 0, truncated: false });
  return { actor, record, run: () => actor.openSessionBeforeInput('synthetic', new AbortController().signal) };
}
describe('session-start handle evidence without unknown-handle adoption', () => {
  it('retains the owner-validated rejected handle privately, without task input, active adoption or closure', async () => {
    const h = harness(false);
    await expect(h.run()).rejects.toThrow('unknown_attached_session');
    expect(h.actor.event).toHaveBeenCalledWith(h.record, 'session_open_rejected', { sessionID: returnedID, attached: true, ownerValidated: true, admitted: false, inputDispatched: false, reason: 'unknown_attached_session' });
    expect(h.record.sessionID).toBeUndefined();
    expect(h.actor.stamp).not.toHaveBeenCalled();
    expect(h.actor.provider.mock.calls.map((c: any[]) => c[0])).toEqual(['/sessions']);
  });
  it('never retains or adopts a handle from a different owner', async () => {
    const h = harness(false, 'different-owner');
    await expect(h.run()).rejects.toThrow('invalid_owner');
    expect(h.actor.event).not.toHaveBeenCalled(); expect(h.record.sessionID).toBeUndefined();
    expect(h.actor.provider).toHaveBeenCalledTimes(1);
  });
  it('retains an admitted handle before the first log read can fail, without reopening on a generic failure', async () => {
    const h = harness(true), provider = h.actor.provider;
    h.actor.provider = vi.fn(async (...args: unknown[]) => {
      if (String(args[0]).includes('/log?')) throw new SidecarHTTPError(500);
      return provider(...args);
    });
    await expect(h.run()).rejects.toThrow();
    expect(h.record.sessionID).toBe(returnedID);
    expect(h.actor.stamp).toHaveBeenCalledTimes(1);
    expect(h.actor.provider).toHaveBeenCalledTimes(2);
  });
});
