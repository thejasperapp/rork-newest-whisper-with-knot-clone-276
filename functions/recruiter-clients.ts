import { meetingUUID } from './jasper-meeting-rules';
import { clientStages, emptyRecruiterClient, reviewedTeamCard, updateRecruiterClient, type RecruiterClient, type RecruiterTeamCard } from './recruiter-client-rules';
type ClientEnv = { SUPABASE_SERVICE_ROLE_KEY?: string };

type Store = { read<T>(key: string): T | undefined; write(key: string, value: unknown): void; remove(key: string): void; list<T>(prefix: string): { key: string; value: T }[] };
type Rows = <T>(table: string, params: Record<string, string>, service?: boolean) => Promise<T[]>;
type Prospect = { id: string; recruiter_id: string; status: string; updated_at: string };
const base = 'https://uryyyegnbtlmyhqlgndy.supabase.co';

async function prospect(rows: Rows, owner: string, id: string): Promise<Prospect> {
  if (!meetingUUID.test(id)) throw new Error('invalid_client');
  const found = await rows<Prospect>('whisper_recruiter_prospects', { select: 'id,recruiter_id,status,updated_at', id: `eq.${id}`, recruiter_id: `eq.${owner}`, limit: '1' });
  if (!found.length || found[0].recruiter_id !== owner) throw new Error('client_access_denied');
  return found[0];
}
/** Called on every team operation; neither a cached seat nor a supplied business ID grants access. */
async function teamMembers(rows: Rows, business: string, caller: string): Promise<Set<string>> {
  if (!meetingUUID.test(business)) throw new Error('team_access_denied');
  const plans = await rows<{ user_id: string }>('whisper_business_plus', { select: 'user_id', user_id: `eq.${business}`, status: 'eq.active', limit: '1' });
  if (!plans.length) throw new Error('team_access_denied');
  const members = await rows<{ user_id: string }>('whisper_business_team', { select: 'user_id', business_id: `eq.${business}`, limit: '501' });
  if (members.length > 500) throw new Error('narrow_search');
  const ids = new Set([business, ...members.map((m) => m.user_id)]);
  if (!ids.has(caller)) throw new Error('team_access_denied');
  return ids;
}

export async function recruiterClientsRoute(request: Request, env: ClientEnv, owner: string, partition: string, store: Store, rows: Rows, body: () => Promise<Record<string, unknown>>, meetings: () => Promise<{ id: string }[]>): Promise<unknown> {
  const url = new URL(request.url), path = url.pathname;
  const team = path === '/jasper-meetings/clients/team';
  if (!team && partition !== owner) throw new Error('client_access_denied');
  if (!['GET', 'POST'].includes(request.method)) throw new Error('invalid_action');
  if (team) {
    const business = url.searchParams.get('businessId') ?? '';
    if (partition !== business) throw new Error('team_access_denied');
    const input = request.method === 'POST' ? await body() : null;
    // A former member can still revoke their own card, never read or publish into the former team.
    if (input?.action === 'revoke') {
      if (!meetingUUID.test(String(input.id ?? '')) || input.confirm !== true) throw new Error('invalid_client');
      const key = `teamcard:${owner}:${input.id}`;
      const revisionKey = `teamrevision:${owner}:${input.id}`;
      const previous = store.read<RecruiterTeamCard>(key);
      if (!previous && store.read<number>(revisionKey) === undefined) return { revoked: true };
      store.write(revisionKey, (store.read<number>(revisionKey) ?? previous?.revision ?? 0) + 1);
      store.remove(key);
      return { revoked: true };
    }
    const members = await teamMembers(rows, business, owner);
    if (input) {
      const id = String(input.id ?? '');
      await prospect(rows, owner, id);
      await teamMembers(rows, business, owner);
      const key = `teamcard:${owner}:${id}`;
      const previous = store.read<RecruiterTeamCard>(key);
      const revisionKey = `teamrevision:${owner}:${id}`;
      const revision = store.read<number>(revisionKey) ?? previous?.revision ?? 0;
      if (input.revision !== revision) throw new Error('revision_conflict');
      const card = reviewedTeamCard(input, owner, id, revision);
      if (!previous && store.list('teamcard:').length >= 500) throw new Error('client_limit');
      store.write(key, card); store.write(revisionKey, card.revision);
      return card;
    }
    const candidates = store.list<RecruiterTeamCard>('teamcard:').map((row) => row.value).filter((card) => members.has(card.publisherId));
    const live = new Set<string>();
    // Elevated read is narrowly limited to ownership/existence, never contact or meeting content.
    for (let offset = 0; offset < candidates.length; offset += 100) {
      const ids = candidates.slice(offset, offset + 100).map((c) => c.id);
      const existing = await rows<{ id: string; recruiter_id: string }>('whisper_recruiter_prospects', { select: 'id,recruiter_id', id: `in.(${ids.join(',')})`, limit: '100' }, true);
      existing.forEach((p) => live.add(`${p.recruiter_id}:${p.id}`));
    }
    const currentMembers = await teamMembers(rows, business, owner);
    // Re-read after awaits so a completed revoke cannot reappear from an earlier snapshot.
    return { revisions: Object.fromEntries(store.list<number>(`teamrevision:${owner}:`).map((r) => [r.key.split(':')[2], r.value])), cards: store.list<RecruiterTeamCard>('teamcard:').map((r) => r.value).filter((c) => currentMembers.has(c.publisherId) && live.has(`${c.publisherId}:${c.id}`)) };
  }
  if (path.endsWith('/teams') && request.method === 'GET') {
    const seats = await rows<{ business_id: string }>('whisper_business_team', { select: 'business_id', user_id: `eq.${owner}`, limit: '101' });
    if (seats.length > 100) throw new Error('narrow_search');
    const ids = [...new Set([owner, ...seats.map((s) => s.business_id)])];
    const teams = await rows<{ user_id: string; company_name: string | null }>('whisper_business_plus', { select: 'user_id,company_name', user_id: `in.(${ids.join(',')})`, status: 'eq.active', limit: '200' });
    return { teams: [...new Map(teams.map((t) => [t.user_id, { id: t.user_id, name: t.company_name || 'Business team' }])).values()] };
  }
  if (path.endsWith('/promotions') && request.method === 'GET') {
    const period = url.searchParams.get('period') ?? new Date().toISOString().slice(0, 7);
    if (!/^20\d{2}-(0[1-9]|1[0-2])$/.test(period)) throw new Error('invalid_client');
    const start = `${period}-01T00:00:00.000Z`, end = new Date(Date.UTC(Number(period.slice(0, 4)), Number(period.slice(5)), 1)).toISOString();
    type Promotion = { id: string; promoted_id: string; promoted_username: string; role: string; created_at: string };
    const records: Promotion[] = [];
    let after = '';
    for (;;) {
      const page = await rows<Promotion>('whisper_recruiter_promotions', { select: 'id,promoted_id,promoted_username,role,created_at', recruiter_id: `eq.${owner}`, and: `(created_at.gte.${start},created_at.lt.${end})`, ...(after ? { id: `gt.${after}` } : {}), order: 'id.asc', limit: '200' });
      if (page.some((r, i) => !meetingUUID.test(r.id) || !meetingUUID.test(r.promoted_id) || (after && r.id <= after) || (i > 0 && r.id <= page[i - 1].id))) throw new Error('meeting_read_failed');
      records.push(...page);
      if (records.length > 10000) throw new Error('narrow_search');
      if (page.length < 200) break;
      after = page[page.length - 1].id;
    }
    return { period, start, end, recordCount: records.length, peopleCount: new Set(records.map((r) => r.promoted_id)).size, records };
  }
  if (path.endsWith('/list') && request.method === 'GET') {
    const owned: Prospect[] = [];
    let after = '';
    for (;;) {
      const page = await rows<Prospect>('whisper_recruiter_prospects', { select: 'id,recruiter_id,status,updated_at', recruiter_id: `eq.${owner}`, ...(after ? { id: `gt.${after}` } : {}), order: 'id.asc', limit: '200' });
      if (page.some((r, i) => !meetingUUID.test(r.id) || r.recruiter_id !== owner || (after && r.id <= after) || (i > 0 && r.id <= page[i - 1].id))) throw new Error('meeting_read_failed');
      owned.push(...page);
      if (owned.length > 1000) throw new Error('client_limit');
      if (page.length < 200) break;
      after = page[page.length - 1].id;
    }
    return { clients: Object.fromEntries(owned.map((p) => [p.id, reconcileStage(store, p)])) };
  }
  const id = url.searchParams.get('id') ?? '';
  const p = await prospect(rows, owner, id);
  if (request.method === 'GET') return reconcileStage(store, p);
  const input = await body();
  if (path.endsWith('/stage')) {
    if (typeof input.stage !== 'string' || !clientStages.includes(input.stage) || input.expectedStage !== p.status || input.expectedUpdatedAt !== (p.updated_at ?? null)) throw new Error('revision_conflict');
    if (input.stage === p.status) return reconcileStage(store, p);
    const at = new Date().toISOString();
    // Persist intent before the remote write; an interrupted response is reconciled on the next read.
    store.write(`clientstage:${id}`, { stage: input.stage, at, version: at });
    const target = new URL(`${base}/rest/v1/whisper_recruiter_prospects`);
    target.searchParams.set('id', `eq.${id}`); target.searchParams.set('recruiter_id', `eq.${owner}`); target.searchParams.set('status', `eq.${p.status}`); target.searchParams.set('updated_at', p.updated_at ? `eq.${p.updated_at}` : 'is.null'); target.searchParams.set('select', 'id,recruiter_id,status,updated_at');
    const response = await fetch(target, { method: 'PATCH', headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY ?? '', Authorization: request.headers.get('Authorization') ?? '', 'Content-Type': 'application/json', Prefer: 'return=representation' }, body: JSON.stringify({ status: input.stage, updated_at: at }), signal: AbortSignal.timeout(15000) });
    if (!response.ok) { store.remove(`clientstage:${id}`); throw new Error('client_save_failed'); }
    const changed = await response.json() as Prospect[];
    if (changed.length !== 1) { store.remove(`clientstage:${id}`); throw new Error('revision_conflict'); }
    store.write(`clientstage:${id}`, { stage: input.stage, at: changed[0].updated_at || at, version: changed[0].updated_at });
    return reconcileStage(store, changed[0]);
  }
  if (!path.endsWith('/profile')) throw new Error('invalid_action');
  const current = reconcileStage(store, p);
  const next = updateRecruiterClient(current, input);
  const oldIDs = new Set(current.meetingIds);
  if (next.meetingIds.some((meeting) => !oldIDs.has(meeting))) {
    const accessible = new Set((await meetings()).map((m) => m.id));
    if (next.meetingIds.some((meeting) => !oldIDs.has(meeting) && !accessible.has(meeting))) throw new Error('meeting_access_denied');
  }
  if ((store.read<RecruiterClient>(`client:${id}`)?.revision ?? 0) !== current.revision) throw new Error('revision_conflict');
  if (!store.read(`client:${id}`) && store.list('client:').length >= 1000) throw new Error('client_limit');
  store.write(`client:${id}`, next);
  return next;
}
function reconcileStage(store: Store, p: Prospect): RecruiterClient {
  const current = store.read<RecruiterClient>(`client:${p.id}`) ?? emptyRecruiterClient(p.status);
  const pending = store.read<{ stage: string; at: string; version: string }>(`clientstage:${p.id}`);
  if (pending?.stage === p.status && pending.version === p.updated_at) {
    current.stage = p.status; current.stageEnteredAt = pending.at;
    current.stageHistory = [...current.stageHistory, pending].slice(-100); current.revision++;
    store.write(`client:${p.id}`, current); store.remove(`clientstage:${p.id}`);
  } else if (current.stage !== p.status) {
    // Older clients may still move stages directly; do not fabricate their transition time.
    current.stage = p.status; current.stageEnteredAt = null; current.revision++;
    store.write(`client:${p.id}`, current);
  }
  if (pending) store.remove(`clientstage:${p.id}`);
  return current;
}
