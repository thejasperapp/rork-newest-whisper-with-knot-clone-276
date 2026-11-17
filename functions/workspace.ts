import { managesWork, newWork, transitionWork, workDate, workID, workText, workView, type IntakeSettings, type WorkAccess, type WorkItem, type WorkPerson } from './workspace-rules';

type Store = { read<T>(key: string): T | undefined; write(key: string, value: unknown): void; list<T>(prefix: string): { key: string; value: T }[] };
type Rows = <T>(table: string, params: Record<string, string>, service?: boolean) => Promise<T[]>;
/** Team membership is checked with narrowly scoped elevated reads, not platform role labels. */
async function members(rows: Rows, space: string, team: boolean): Promise<Set<string>> {
  if (!team) return new Set([space]);
  const plans = await rows<{ user_id: string }>('whisper_business_plus', { select: 'user_id', user_id: `eq.${space}`, status: 'eq.active', limit: '1' }, true);
  if (!plans.length) throw new Error('workspace_access_denied');
  const seats = await rows<{ user_id: string }>('whisper_business_team', { select: 'user_id', business_id: `eq.${space}`, limit: '501' }, true);
  if (seats.length > 500) throw new Error('work_limit');
  return new Set([space, ...seats.map((s) => s.user_id)]);
}
async function person(rows: Rows, username: unknown): Promise<WorkPerson> {
  const name = workText(username, 40, true).replace(/^@/, '');
  if (!/^[a-zA-Z0-9_.]+$/.test(name)) throw new Error('invalid_work');
  const found = await rows<{ user_id: string; username: string }>('whisper_profiles', { select: 'user_id,username', username: `ilike.${name}`, limit: '2' }, true);
  if (found.length !== 1 || found[0].username.toLowerCase() !== name.toLowerCase()) throw new Error('work_person_missing');
  return { id: workID(found[0].user_id), username: found[0].username };
}
/** Runs in the account actor's serialized queue; every write uses a reviewed revision. */
export async function workspaceRoute(request: Request, caller: string, partition: string, store: Store, rows: Rows, body: () => Promise<Record<string, unknown>>): Promise<unknown> {
  const url = new URL(request.url), space = workID(url.searchParams.get('space') ?? caller), team = url.searchParams.get('team') === '1';
  if (!/^\/jasper-meetings\/workspace(?:\/(?:intake|members|item\/[0-9a-f-]{36}))?$/.test(url.pathname)) throw new Error('invalid_action');
  if (partition !== space) throw new Error('workspace_access_denied');
  if (!['GET', 'POST'].includes(request.method)) throw new Error('invalid_action');
  const prefix = `work:${team ? 'team' : 'private'}:`, intakeKey = `${prefix}intake`;
  let seats = await members(rows, space, team);
  const access: WorkAccess = { caller, owner: caller === space, member: seats.has(caller) };
  const settings = (): IntakeSettings => store.read<IntakeSettings>(intakeKey) ?? { revision: 0, people: [], instructions: 'Describe what you need, why it matters, and the expected outcome.', assigneeId: space, turnaroundDays: 7 };
  const canSubmit = (): boolean => access.member || settings().people.some((p) => p.id === caller);
  const input = request.method === 'POST' ? await body() : null;
  // Profile lookup precedes the final permission check and synchronous commit.
  let invitee: WorkPerson | undefined;
  if (input && ['publish', 'invite_requester'].includes(String(input.action))) {
    if (!access.member) throw new Error('workspace_access_denied');
    invitee = await person(rows, input.username);
  }
  if (input) { seats = await members(rows, space, team); access.member = seats.has(caller); request.signal.throwIfAborted(); }
  if (url.pathname.endsWith('/intake')) {
    if (!access.owner || !access.member) throw new Error('workspace_access_denied');
    const current = settings();
    if (!input) return current;
    if (input.revision !== current.revision || input.confirm !== true) throw new Error('revision_conflict');
    if (input.action === 'invite_requester' && invitee) {
      if (!current.people.some((p) => p.id === invitee.id)) current.people.push(invitee);
      if (current.people.length > 100) throw new Error('work_limit');
    } else if (input.action === 'revoke_requester') current.people = current.people.filter((p) => p.id !== workID(input.userId));
    else if (input.action === 'configure_intake') {
      current.instructions = workText(input.instructions, 2000, true);
      current.assigneeId = workID(input.assigneeId);
      if (!seats.has(current.assigneeId)) throw new Error('workspace_access_denied');
      if (!Number.isInteger(input.turnaroundDays) || Number(input.turnaroundDays) < 1 || Number(input.turnaroundDays) > 90) throw new Error('invalid_work');
      current.turnaroundDays = Number(input.turnaroundDays);
    } else throw new Error('invalid_action');
    current.revision++; store.write(intakeKey, current); return current;
  }
  if (url.pathname.endsWith('/members')) {
    if (!access.member || input) throw new Error('workspace_access_denied');
    const result: WorkPerson[] = [];
    const ids = [...seats];
    for (let offset = 0; offset < ids.length; offset += 100) {
      const profiles = await rows<{ user_id: string; username: string }>('whisper_profiles', { select: 'user_id,username', user_id: `in.(${ids.slice(offset, offset + 100).join(',')})`, limit: '100' }, true);
      result.push(...profiles.map((p) => ({ id: p.user_id, username: p.username })));
    }
    if (!(await members(rows, space, team)).has(caller)) throw new Error('workspace_access_denied');
    return { people: result };
  }
  if (!input) {
    const id = url.pathname.includes('/item/') ? url.pathname.split('/').pop() : url.searchParams.get('id');
    if (id) {
      const item = store.read<WorkItem>(`${prefix}item:${workID(id)}`);
      const view = item ? workView(item, access, canSubmit()) : null;
      if (!view) throw new Error('workspace_access_denied');
      return view;
    }
    const items = store.list<WorkItem>(`${prefix}item:`).map((r) => workView(r.value, access, canSubmit())).filter((i) => i !== null).map((i) => ({ id: i.id, kind: i.kind, title: i.title, status: i.status, deadline: i.deadline, reviewOn: i.reviewOn, assigneeId: i.assigneeId, revision: i.revision, updatedAt: i.updatedAt, external: i.external }));
    if (!access.member && !canSubmit() && !items.length) throw new Error('workspace_access_denied');
    return { items, member: access.member, owner: access.owner, canSubmit: canSubmit(), intakeInstructions: canSubmit() ? settings().instructions : '', checkedAt: new Date().toISOString() };
  }
  const action = String(input.action ?? ''), key = `${prefix}item:${workID(input.id)}`;
  if (input.confirm !== true) throw new Error('confirmation_required');
  if (action === 'create') {
    if (!access.member && (input.kind !== 'request' || !canSubmit())) throw new Error('workspace_access_denied');
    const existing = store.read<WorkItem>(key);
    if (existing) { if (existing.createdBy !== caller) throw new Error('workspace_access_denied'); return workView(existing, access, canSubmit()); }
    const saved = store.list<WorkItem>(`${prefix}item:`).map((r) => r.value);
    if (saved.length >= 900 || saved.filter((i) => i.status !== 'archived').length >= 200) throw new Error('work_limit');
    if (!access.member && (saved.length >= 700 || saved.filter((i) => i.createdBy === caller && i.status !== 'archived').length >= 10 || saved.filter((i) => i.createdBy === caller && i.createdAt.slice(0, 10) === new Date().toISOString().slice(0, 10)).length >= 20)) throw new Error('work_limit');
    const intake = settings();
    const assignee = access.member ? workID(input.assigneeId ?? caller) : seats.has(intake.assigneeId) ? intake.assigneeId : space;
    if (!seats.has(assignee)) throw new Error('workspace_access_denied');
    const sanitized = access.member ? input : { ...input, deadline: new Date(Date.now() + intake.turnaroundDays * 86400000).toISOString().slice(0, 10), reviewOn: '' };
    const item = newWork(sanitized, caller, assignee);
    store.write(key, item); return workView(item, access, canSubmit());
  }
  const item = store.read<WorkItem>(key);
  if (!item || !workView(item, access, canSubmit())) throw new Error('workspace_access_denied');
  if (input.revision !== item.revision) throw new Error('revision_conflict');
  if (item.status === 'archived') throw new Error('invalid_transition');
  const removingAccess = ['revoke', 'archive'].includes(action);
  if (!removingAccess && (item.events.length >= 500 || (action === 'comment' && item.comments.length >= 200))) throw new Error('work_limit');
  const manager = managesWork(item, access), now = new Date().toISOString();
  if (action === 'comment') {
    const audience = input.audience === 'internal' ? 'internal' : 'shared';
    if (!access.member && audience === 'internal') throw new Error('workspace_access_denied');
    if (item.kind === 'decision' && item.status !== 'discussing') throw new Error('invalid_transition');
    item.comments.push({ id: crypto.randomUUID(), author: caller, text: workText(input.text, 2000, true), audience, at: now });
  } else if (action === 'reassign_reviewer') {
    if (!access.owner || !access.member || item.kind !== 'decision' || item.status !== 'decided') throw new Error('workspace_access_denied');
    const assignee = workID(input.assigneeId);
    if (!seats.has(assignee)) throw new Error('workspace_access_denied');
    item.assigneeId = assignee;
  } else if (action === 'edit') {
    if (!manager || ['decided', 'reviewed', 'completed', 'declined'].includes(item.status)) throw new Error('workspace_access_denied');
    const previousContent = JSON.stringify([item.title, item.brief, item.deadline, item.assigneeId]);
    item.title = workText(input.title, 160, true); item.brief = workText(input.brief, 8000, true);
    item.alternatives = workText(input.alternatives ?? '', 4000); item.internalNote = workText(input.internalNote ?? '', 4000);
    item.deadline = workDate(input.deadline); item.reviewOn = workDate(input.reviewOn);
    if (input.assigneeId !== item.assigneeId && !access.owner) throw new Error('workspace_access_denied');
    item.assigneeId = workID(input.assigneeId);
    if (!seats.has(item.assigneeId)) throw new Error('workspace_access_denied');
    // Changed decision options reopen discussion rather than keeping obsolete assent.
    if (item.kind === 'decision') item.status = 'draft';
    if (item.kind === 'request' && previousContent !== JSON.stringify([item.title, item.brief, item.deadline, item.assigneeId])) {
      item.status = 'submitted'; item.outcome = '';
    }
  } else if (action === 'publish') {
    if (!manager || item.kind !== 'delivery' || !invitee || item.versions.length >= 30) throw new Error('workspace_access_denied');
    const raw = workText(input.url ?? '', 2000);
    if (raw) { let link: URL; try { link = new URL(raw); } catch { throw new Error('invalid_work'); } if (link.protocol !== 'https:' || link.username || link.password) throw new Error('invalid_work'); }
    const version = { number: item.versions.length + 1, title: workText(input.title, 160, true), summary: workText(input.summary, 6000, true), url: raw, milestones: workText(input.milestones ?? '', 3000), at: now };
    if (item.client?.id !== invitee.id) item.comments = item.comments.map((c) => ({ ...c, audience: 'internal' }));
    item.client = invitee; item.versions.push(version); item.publishedVersion = version.number; item.status = 'in_review';
  } else if (action === 'revoke') {
    if (!manager || item.kind !== 'delivery') throw new Error('workspace_access_denied');
    item.publishedVersion = null; item.status = 'draft';
  } else if (action === 'respond') {
    const version = item.versions.find((v) => v.number === item.publishedVersion);
    if (item.kind !== 'delivery' || item.client?.id !== caller || !version || version.response || input.version !== version.number || !['accepted', 'changes_requested'].includes(String(input.status))) throw new Error('invalid_transition');
    version.response = { status: input.status as 'accepted' | 'changes_requested', text: workText(input.text ?? '', 2000, input.status === 'changes_requested'), actor: caller, at: now };
    item.status = version.response.status;
  } else transitionWork(item, access, action, workText(input.text ?? '', 2000));
  item.revision++; item.updatedAt = now; item.events.push({ id: crypto.randomUUID(), actor: caller, action, at: now, contentRevision: item.revision - 1, ...(['approve', 'decline', 'decide', 'review'].includes(action) ? { detail: workText(input.text ?? '', 2000) } : {}) });
  // Content additions leave room for approval, feedback and final lifecycle events.
  const addsContent = ['comment', 'publish', 'edit'].includes(action);
  if (addsContent && (item.events.length > 450 || JSON.stringify(item).length > 150000)) throw new Error('work_limit');
  if (!removingAccess && JSON.stringify(item).length > 180000) throw new Error('work_limit');
  store.write(key, item);
  return workView(item, access, canSubmit()) ?? { saved: true };
}
