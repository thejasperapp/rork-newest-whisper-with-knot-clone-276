// @vitest-environment node
// In-memory fixtures only: no provider calls, sessions or live owner messages.
import { afterEach, describe, expect, it, vi } from 'vitest';
import { DatabaseSync } from 'node:sqlite';
vi.mock('cloudflare:workers', () => ({ DurableObject: class { constructor(protected ctx: unknown, protected env: unknown) {} } }));
import { KnotConversationAccount } from '../../functions/knot-conversations';
import { safeKnotActivityDetail } from '../../functions/knot-activity';
import { applyKnotActivityFrame, currentKnotActivity, emptyKnotActivity, finishKnotActivity, knotActivityTimeline } from '../../functions/knot-current-activity';
import { knotToolsWithAgentActivity, validatedKnotAgentActivity } from '../../functions/knot-agent-presentation';
import { knotProviderToolCalls, validatedKnotSelection, validatedKnotSelectionPrefix } from '../../functions/knot-tool-selection';
const id = (n: number) => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');
const databases: DatabaseSync[] = [];
afterEach(() => { databases.splice(0).forEach(db => db.close()); vi.useRealTimers(); vi.restoreAllMocks(); });
const tool = { type: 'function', function: { name: 'session_input', parameters: { type: 'object', properties: { data: { type: 'string' } }, required: ['data'], additionalProperties: false } } };
const envelope = (...args: unknown[]) => ({ choices: [{ finish_reason: 'tool_calls', message: { tool_calls: args.map((value, index) => ({ id: 'call_' + index, type: 'function', function: { name: 'session_input', arguments: JSON.stringify(value) } })) } }] });
describe('active-agent exact presentation transport', () => {
  it('retains different object-specific labels without passing presentation into execution', () => {
    const sequences = [
      ['Read trail reference', 'Compose trail guide', 'Check trail pages'],
      ['Read orbit rules', 'Build orbit controls', 'Check orbit input'],
    ];
    for (const labels of sequences) for (const label of labels) {
      const activity = { label, purpose: 'Inspect the actual requested object.' };
      const [selected] = validatedKnotSelection(envelope({ data: 'printf fixture', _activity: activity }), knotToolsWithAgentActivity([tool]), 1, new Set());
      expect(selected.activity).toEqual(activity);
      expect(JSON.parse(selected.function.arguments)).toEqual({ data: 'printf fixture' });
    }
    expect(sequences[0].some(label => sequences[1].includes(label))).toBe(false);
  });
  it('keeps authored activity inside provider arguments, never as a local envelope field', () => {
    const activity = { label: ' Read orbit rules ', purpose: ' Check the orbit controls. ' };
    const [selected] = validatedKnotSelection(envelope({ data: 'printf fixture', _activity: activity }), knotToolsWithAgentActivity([tool]), 1, new Set());
    const [history] = knotProviderToolCalls([selected]);
    expect(Object.keys(history).sort()).toEqual(['function', 'id', 'type']);
    expect(JSON.parse(history.function.arguments)).toEqual({ data: 'printf fixture', _activity: activity });
    expect(JSON.parse(selected.function.arguments)).toEqual({ data: 'printf fixture' });
    expect(selected.activity).toEqual(activity);
  });
  it('preserves exact authored wording through header state and retained Events', () => {
    const activity = { label: ' Read  orbit rules ', purpose: ' Check  orbit controls. ' };
    const detail = { stepID: 'orbit-read', stepLabel: activity.label, stepPurpose: activity.purpose };
    expect(safeKnotActivityDetail(detail)).toEqual(detail);
    const state = emptyKnotActivity();
    expect(applyKnotActivityFrame(state, { activityID: 'orbit-read', ...activity, tool: 'session_input', phase: 'open' }, 1000)).toBe(true);
    expect(currentKnotActivity(state, id(2), false, 1800)?.label).toBe(activity.label);
    finishKnotActivity(state, 2000);
    expect(knotActivityTimeline(state, 2000)[0]).toMatchObject(activity);
    expect(currentKnotActivity(state, id(2), true, 2000)).toBeNull();
  });
  it('requires safe authored metadata, without trimming or inventing labels', () => {
    expect(validatedKnotAgentActivity({ label: ' Read orbit rules ', purpose: ' Check orbit rules. ' })).toEqual({ label: ' Read orbit rules ', purpose: ' Check orbit rules. ' });
    for (const activity of [undefined, {}, { label: 'x', purpose: 'y', command: 'x' }, { label: '<markup>', purpose: 'x' }, { label: 'x\n', purpose: 'y' }]) {
      expect(() => validatedKnotSelection(envelope({ data: 'printf fixture', _activity: activity }), knotToolsWithAgentActivity([tool]), 1, new Set())).toThrow();
    }
  });
  it('normalizes a valid prefix without granting execution to a malformed tail', () => {
    const activity = { label: 'Read orbit rules', purpose: 'Inspect the rules for the orbit game.' };
    const result = validatedKnotSelectionPrefix(envelope({ data: 'printf fixture', _activity: activity }, { data: 'bad' }), knotToolsWithAgentActivity([tool]), 2, new Set());
    expect(result.rejected?.index).toBe(1);
    expect(result.calls[0].activity).toEqual(activity);
    expect(JSON.parse(result.calls[0].function.arguments)).toEqual({ data: 'printf fixture' });
  });
});
function fixture() {
  const db = new DatabaseSync(':memory:'); databases.push(db);
  const sql = { exec(query: string, ...values: (string | number | null)[]) {
    const statement = db.prepare(query), rows = statement.columns().length ? statement.all(...values) : (statement.run(...values), []);
    return { toArray: () => rows, one: () => { if (rows.length !== 1) throw new Error('Expected one row'); return rows[0]; }, [Symbol.iterator]: () => rows[Symbol.iterator]() };
  } };
  const ctx = { id: { name: id(9) }, storage: { sql, transactionSync: (f: () => unknown) => { db.exec('BEGIN'); try { const value = f(); db.exec('COMMIT'); return value; } catch (error) { db.exec('ROLLBACK'); throw error; } } } } as never;
  const actor = new KnotConversationAccount(ctx, {} as never);
  const post = (path: string, body: Record<string, unknown>, owner = id(9)) => actor.fetch(new Request('https://internal' + path, { method: 'POST', headers: { 'X-Knot-Owner': owner }, body: JSON.stringify({ bot: 'main', conversationID: id(1), requestID: id(2), sourceMessageID: id(3), ...body }) }));
  const reaction = (action: string, body: Record<string, unknown> = {}) => post('/internal/reactions/' + action, body);
  const begin = (body: Record<string, unknown> = {}) => reaction('begin', { supported: true, text: 'I finished my orbit game!', ...body });
  const apply = (emoji: string, body: Record<string, unknown> = {}) => reaction('apply', { messageID: id(3), callID: 'first', emoji, ...body });
  return { db, sql, post, reaction, begin, apply };
}
describe('source-bound semantic reactions and silent terminals', () => {
  it('permits one unrestricted semantic choice, preserves retries and rejects a different choice', async () => {
    const f = fixture(); expect((await f.begin()).status).toBe(200);
    expect(await (await f.apply('👩🏾‍🚀')).json()).toMatchObject({ emoji: '👩🏾‍🚀', changed: true });
    expect(await (await f.apply('👩🏾‍🚀')).json()).toMatchObject({ changed: false });
    expect((await f.apply('🥳', { callID: 'second' })).status).toBe(409);
    expect(f.sql.exec('SELECT * FROM reactions').toArray()).toHaveLength(1);
  });
  it('keeps the semantic latch after request ledgers expire', async () => {
    const f = fixture(); await f.begin(); await f.apply('🪼');
    f.sql.exec('DELETE FROM reaction_turns'); f.sql.exec('DELETE FROM reaction_calls'); f.sql.exec('DELETE FROM reaction_events');
    await f.begin({ requestID: id(4) });
    expect((await f.apply('❤️‍🔥', { requestID: id(4) })).status).toBe(409);
    expect(await (await f.apply('🪼', { requestID: id(4) })).json()).toMatchObject({ changed: false });
  });
  it('has no message-count or time gate for a different source', async () => {
    const f = fixture(); await f.begin(); await f.apply('🥳');
    expect(await (await f.begin({ requestID: id(4), sourceMessageID: id(5), text: 'I am grieving today.' })).json()).toMatchObject({ ready: true });
    expect(await (await f.apply('🫂', { requestID: id(4), sourceMessageID: id(5), messageID: id(5) })).json()).toMatchObject({ emoji: '🫂', changed: true });
  });
  it('separates runtime acknowledgment from semantic choice and never overwrites it later', async () => {
    const f = fixture(); await f.begin();
    expect((await f.apply('🪼', { origin: 'runtime_long_work' })).status).toBe(400);
    expect(await (await f.apply('👍', { origin: 'runtime_long_work' })).json()).toMatchObject({ changed: true });
    expect(await (await f.apply('🥳', { callID: 'semantic' })).json()).toMatchObject({ emoji: '🥳', changed: true });
    expect(await (await f.apply('👍', { origin: 'runtime_long_work', callID: 'retry' })).json()).toMatchObject({ emoji: '🥳', changed: false });
  });
  it('respects semantic opt-out while allowing runtime-only acknowledgment and refuses late/wrong-owner calls', async () => {
    const f = fixture(); expect(await (await f.begin({ text: 'No emojis please' })).json()).toMatchObject({ ready: false, runtimeReady: true });
    expect((await f.apply('🫂')).status).toBe(409);
    expect((await f.apply('👍', { origin: 'runtime_long_work' })).status).toBe(200);
    expect((await f.post('/internal/reactions/apply', {}, id(8))).status).toBe(401);
    await f.reaction('close'); expect((await f.apply('👍', { origin: 'runtime_long_work' })).status).toBe(409);
  });
  it('durably acknowledges a blank terminal without inserting a bubble or allowing a late replacement', async () => {
    const f = fixture(), body = { taskID: id(2), sourceMessageID: id(2), replyID: id(6), text: 'Create an orbit game' };
    expect((await f.post('/internal/owned-turns/reserve', body)).status).toBe(200);
    expect((await f.post('/internal/owned-turns/deliver', { ...body, text: '' })).status).toBe(400);
    for (let i = 0; i < 2; i++) expect(await (await f.post('/internal/owned-turns/deliver', { ...body, text: '', silent: true })).json()).toMatchObject({ ok: true, silent: true });
    expect(f.sql.exec('SELECT * FROM messages').toArray()).toHaveLength(1);
    expect((await f.post('/internal/owned-turns/deliver', { ...body, text: 'Late fallback' })).status).toBe(410);
  });
  it('refuses silent delivery after Stop releases the binding', async () => {
    const f = fixture(), body = { taskID: id(2), sourceMessageID: id(2), replyID: id(6), text: 'Create an orbit game' };
    await f.post('/internal/owned-turns/reserve', body); await f.post('/internal/owned-turns/release', body);
    expect((await f.post('/internal/owned-turns/deliver', { ...body, text: '', silent: true })).status).toBe(410);
    expect(f.sql.exec('SELECT * FROM messages').toArray()).toHaveLength(1);
  });
});
