// @vitest-environment node
import { afterEach, describe, expect, it, vi } from 'vitest';
import { recruiterClientsRoute } from '../../../functions/recruiter-clients';
import { emptyRecruiterClient, type RecruiterClient, type RecruiterTeamCard } from '../../../functions/recruiter-client-rules';
const owner = '10000000-0000-4000-8000-000000000001';
const other = '10000000-0000-4000-8000-000000000002';
const business = '10000000-0000-4000-8000-000000000003';
const id = '10000000-0000-4000-8000-000000000004';
const meeting = '10000000-0000-4000-8000-000000000005';
class MemoryStore {
  data = new Map<string, unknown>();
  read<T>(key: string): T | undefined { const v = this.data.get(key); return v === undefined ? undefined : structuredClone(v) as T; }
  write(key: string, value: unknown): void { this.data.set(key, structuredClone(value)); }
  remove(key: string): void { this.data.delete(key); }
  list<T>(prefix: string): { key: string; value: T }[] { return [...this.data.entries()].filter(([k]) => k.startsWith(prefix)).map(([key, value]) => ({ key, value: structuredClone(value) as T })); }
}
function fixture() {
  const store = new MemoryStore();
  const state = { members: [owner, other], exists: true, active: true, status: 'interested', updated: '2026-09-01T00:00:00.000Z' };
  const calls: { table: string; params: Record<string, string>; service?: boolean }[] = [];
  const rows: Parameters<typeof recruiterClientsRoute>[5] = async <T>(table: string, params: Record<string, string>, service?: boolean): Promise<T[]> => {
    calls.push({ table, params, service });
    if (table === 'whisper_business_plus') return (state.active ? [{ user_id: business }] : []) as T[];
    if (table === 'whisper_business_team') return state.members.map((user_id) => ({ user_id, business_id: business })) as T[];
    if (table === 'whisper_recruiter_prospects') return (state.exists && (service || params.recruiter_id === `eq.${owner}`) ? [{ id, recruiter_id: owner, status: state.status, updated_at: state.updated }] : []) as T[];
    return [];
  };
  const call = (path: string, input?: Record<string, unknown>, caller = owner, partition = owner) => recruiterClientsRoute(new Request(`https://example.com/jasper-meetings/clients/${path}`, { method: input ? 'POST' : 'GET', headers: { Authorization: 'Bearer caller-session' } }), {}, caller, partition, store, rows, async () => input ?? {}, async () => [{ id: meeting }]);
  return { store, state, calls, call };
}
const publish = { id, name: 'Creator', role: 'creator', stage: 'interested', update: 'Ready for introduction', confirm: true, revision: 0 };
afterEach(() => vi.unstubAllGlobals());
describe('recruiter private/team route boundaries', () => {
  it('rejects another account partition even for private GET', async () => { const f = fixture(); await expect(f.call(`profile?id=${id}`, undefined, other, owner)).rejects.toThrow('client_access_denied'); });
  it('requires recruiter ownership, not just a known prospect id', async () => { const f = fixture(); await expect(f.call(`profile?id=${id}`, undefined, other, other)).rejects.toThrow('client_access_denied'); });
  it('starts private without writing or publishing anything', async () => { const f = fixture(); expect(await f.call(`profile?id=${id}`)).toEqual(emptyRecruiterClient('interested')); expect(f.store.data.size).toBe(0); });
  it('saves contact data privately and enforces optimistic revisions', async () => {
    const f = fixture(); await f.call(`profile?id=${id}`, { revision: 0, email: 'private@example.com', meetingIds: [meeting] });
    expect(f.store.read<RecruiterClient>(`client:${id}`)?.email).toBe('private@example.com'); expect(f.store.list('teamcard:')).toEqual([]);
    await expect(f.call(`profile?id=${id}`, { revision: 0, email: 'overwrite@example.com' })).rejects.toThrow('revision_conflict');
  });
  it('rejects attaching meetings the owner cannot access', async () => { const f = fixture(); await expect(f.call(`profile?id=${id}`, { revision: 0, meetingIds: [other] })).rejects.toThrow('meeting_access_denied'); expect(f.store.data.size).toBe(0); });
  it('publishes only a reviewed projection and uses minimal existence checks', async () => {
    const f = fixture(); f.store.write(`client:${id}`, { ...emptyRecruiterClient(), email: 'secret' });
    await f.call(`team?businessId=${business}`, { ...publish, email: 'secret', meetingIds: [meeting] }, owner, business);
    const result = await f.call(`team?businessId=${business}`, undefined, other, business) as { cards: RecruiterTeamCard[] };
    expect(result.cards).toHaveLength(1); expect(JSON.stringify(result)).not.toContain('secret'); expect(JSON.stringify(result)).not.toContain(meeting);
    expect(f.calls.filter((c) => c.service).every((c) => c.table === 'whisper_recruiter_prospects' && c.params.select === 'id,recruiter_id')).toBe(true);
  });
  it('requires current membership for reads and publishes', async () => {
    const f = fixture(); f.state.members = [];
    await expect(f.call(`team?businessId=${business}`, undefined, owner, business)).rejects.toThrow('team_access_denied');
    await expect(f.call(`team?businessId=${business}`, publish, owner, business)).rejects.toThrow('team_access_denied');
  });
  it('hides cards if publisher leaves, or the source prospect is deleted', async () => {
    const f = fixture(); await f.call(`team?businessId=${business}`, publish, owner, business);
    f.state.members = [other]; expect((await f.call(`team?businessId=${business}`, undefined, other, business) as { cards: unknown[] }).cards).toEqual([]);
    f.state.members = [owner, other]; f.state.exists = false; expect((await f.call(`team?businessId=${business}`, undefined, other, business) as { cards: unknown[] }).cards).toEqual([]);
  });
  it('revokes only the caller’s card and prevents stale publication replay', async () => {
    const f = fixture(); await f.call(`team?businessId=${business}`, publish, owner, business);
    await f.call(`team?businessId=${business}`, { action: 'revoke', id, confirm: true }, other, business);
    expect(f.store.list('teamcard:')).toHaveLength(1);
    await f.call(`team?businessId=${business}`, { action: 'revoke', id, confirm: true }, owner, business);
    expect(f.store.list('teamcard:')).toHaveLength(0);
    await expect(f.call(`team?businessId=${business}`, publish, owner, business)).rejects.toThrow('revision_conflict');
    await expect(f.call(`team?businessId=${business}`, { ...publish, revision: 1 }, owner, business)).rejects.toThrow('revision_conflict');
    await f.call(`team?businessId=${business}`, { ...publish, revision: 2 }, owner, business);
    expect(f.store.read<RecruiterTeamCard>(`teamcard:${owner}:${id}`)?.revision).toBe(3);
  });
  it('allows a former member to revoke without granting them team read access', async () => {
    const f = fixture(); await f.call(`team?businessId=${business}`, publish, owner, business); f.state.members = [];
    await f.call(`team?businessId=${business}`, { action: 'revoke', id, confirm: true }, owner, business);
    expect(f.store.list('teamcard:')).toEqual([]);
    await expect(f.call(`team?businessId=${business}`, undefined, owner, business)).rejects.toThrow('team_access_denied');
  });
  it('rejects a stale stage snapshot even if the stage cycles back', async () => { const f = fixture(); await expect(f.call(`stage?id=${id}`, { stage: 'ready', expectedStage: 'interested', expectedUpdatedAt: 'old' })).rejects.toThrow('revision_conflict'); });
  it('records confirmed stage time while ordinary profile edits preserve it', async () => {
    const f = fixture(); const before = f.state.updated;
    vi.stubGlobal('fetch', vi.fn(async (_url: URL, init: RequestInit) => { const patch = JSON.parse(String(init.body)); f.state.status = patch.status; f.state.updated = patch.updated_at; return Response.json([{ id, recruiter_id: owner, status: patch.status, updated_at: patch.updated_at }]); }));
    const changed = await f.call(`stage?id=${id}`, { stage: 'ready', expectedStage: 'interested', expectedUpdatedAt: before }) as RecruiterClient;
    expect(changed.stageEnteredAt).toBe(f.state.updated); expect(changed.stageHistory).toHaveLength(1);
    const edited = await f.call(`profile?id=${id}`, { revision: changed.revision, preferences: 'Email first' }) as RecruiterClient;
    expect(edited.stageEnteredAt).toBe(changed.stageEnteredAt);
  });
  it('does not attribute a later unrelated transition to a timed-out intent', async () => {
    const f = fixture(); f.store.write(`clientstage:${id}`, { stage: 'ready', at: '2026-01-01', version: '2026-01-01' }); f.state.status = 'ready';
    expect((await f.call(`profile?id=${id}`) as RecruiterClient).stageEnteredAt).toBeNull(); expect(f.store.read(`clientstage:${id}`)).toBeUndefined();
  });
  it('promotion records use the caller and an explicit bounded UTC month', async () => {
    const f = fixture(); const result = await f.call('promotions?period=2026-12') as { recordCount: number; end: string };
    expect(result.recordCount).toBe(0); expect(result.end).toBe('2027-01-01T00:00:00.000Z');
    const call = f.calls.find((c) => c.table === 'whisper_recruiter_promotions'); expect(call?.params.recruiter_id).toBe(`eq.${owner}`); expect(call?.service).toBeUndefined();
    await expect(f.call('promotions?period=bad')).rejects.toThrow('invalid_client');
  });
});
