// @vitest-environment node
// Pure state and real SQLite actor admission. No provider or shell execution.
import { afterEach, describe, expect, it, vi } from 'vitest';
import { createHash } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
vi.mock('cloudflare:workers', () => ({ DurableObject: class { constructor(protected ctx: unknown, protected env: unknown) {} } }));
import { beginDocumentProgram, appendDocumentProgram, documentProgramInvocation, documentProgramReceipt, claimDocumentProgram, documentPreparationTool, validatedDocumentPreparation, type DocumentProgram, type DocumentProgramOwner } from '../../functions/knot-document-program';
import { documentScriptTool, documentInvocationCommand, type DocumentInvocation } from '../../functions/knot-document-build';
import { KnotShellConversation, type ShellWorkflow } from '../../functions/knot-shell';
import { documentSkillReadCommand, indexedHTMLGameSkill, slicedHTMLArtifact } from '../../functions/knot-document-proof';

const id = (n: number) => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');
const owner: DocumentProgramOwner = { workspace: 'whisper-' + 'a'.repeat(48), bot: 'main', conversationID: id(1), rootID: id(2), parentID: id(3), sourceMessageID: id(4) };
const prep = { stage: 'source' as const, interpreter: 'python3' as const, path: 'synthetic.html', title: '', deliveryLabel: '', authoring: 'author' as const };
const hash = (s: string) => createHash('sha256').update(s).digest('hex');
const begin = () => beginDocumentProgram(owner, prep, 2000, 1000);
const append = (p: DocumentProgram, code: string, final = false) => appendDocumentProgram(p, owner, { index: p.slices.length, prefixSHA256: p.prefixSHA256, code, final }, 1001);
const databases: DatabaseSync[] = [];
afterEach(() => { for (const db of databases.splice(0)) db.close(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });

describe('bounded immutable document programs', () => {
  it('advertises descriptor-only selection and retains historical tool unchanged', () => {
    const before = structuredClone(documentScriptTool), tool = documentPreparationTool(documentScriptTool);
    expect(tool.function.name).toBe('document_prepare');
    expect(tool.function.parameters.properties).not.toHaveProperty('code');
    expect(tool.function.parameters.required).toContain('authoring');
    expect(documentScriptTool).toEqual(before);
    expect(validatedDocumentPreparation(prep)).toEqual(prep);
    for (const invalid of [{ ...prep, code: '' }, { ...prep, authoring: [] }, { ...prep, authoring: { toString: () => 'measure' } }, { ...prep, interpreter: 'knot-doc' }, { ...prep, stage: 'existing' }, { ...prep, path: '../x.html' }]) expect(() => validatedDocumentPreparation(invalid)).toThrow();
    expect(validatedDocumentPreparation({ ...prep, authoring: 'measure' }).authoring).toBe('measure');
    expect(validatedDocumentPreparation({ ...prep, stage: 'build', interpreter: 'knot-doc', path: 'synthetic.pdf', authoring: 'measure' }).authoring).toBe('measure');
    expect(() => validatedDocumentPreparation({ ...prep, stage: 'final', path: 'synthetic.md', authoring: 'measure' })).toThrow();
  });
  it('preserves every byte, independently hashed receipts, and a single claim', async () => {
    const a = await begin(), snapshot = structuredClone(a);
    expect(() => documentProgramInvocation(a, owner, 1001)).toThrow('document_program_closed');
    const first = '# exact 🙂\ntext = "';
    const b = await append(a, first), c = await append(b, 'a\\nb"\n', true);
    expect(a).toEqual(snapshot);
    expect(c.slices[0]).toMatchObject({ sha256: hash(first), prefixSHA256: hash(first) });
    const invocation = documentProgramInvocation(c, owner, 1001);
    expect(invocation.code).toBe(first + 'a\\nb"\n');
    expect(c.prefixSHA256).toBe(hash(invocation.code));
    expect(JSON.stringify(documentProgramReceipt(c))).not.toContain('exact');
    expect(documentProgramReceipt(c)).toMatchObject({ count: 2, state: 'sealed' });
    const claimed = claimDocumentProgram(c, owner, invocation, id(8), 1001);
    expect(c.state).toBe('sealed'); expect(claimed.state).toBe('claimed');
    expect(() => claimDocumentProgram(claimed, owner, invocation, id(9), 1001)).toThrow('document_program_closed');
    expect(() => claimDocumentProgram(c, owner, { ...invocation, code: invocation.code + '#' }, id(9), 1001)).toThrow('document_program_changed');
    await expect(append(c, '#')).rejects.toThrow('document_program_closed');
  });
  it.each(Object.keys(owner) as (keyof DocumentProgramOwner)[])('binds every owner dimension: %s', async key => {
    const p = await append(await begin(), '# synthetic', true), wrong = { ...owner, [key]: owner[key] + '-wrong' };
    await expect(appendDocumentProgram(p, wrong, {}, 1001)).rejects.toThrow('document_program_owner_mismatch');
    expect(() => documentProgramInvocation(p, wrong, 1001)).toThrow('document_program_owner_mismatch');
    expect(() => claimDocumentProgram(p, wrong, documentProgramInvocation(p, owner, 1001), id(9), 1001)).toThrow('document_program_owner_mismatch');
  });
  it.each(['', '\u0000', '\ud800', '\udc00'])('rejects invalid code without changing state: %j', async code => {
    const p = await begin(); await expect(append(p, code)).rejects.toThrow('document_program_invalid'); expect(p.slices).toEqual([]);
  });
  it('rejects duplicate, skipped, stale-prefix, expired and cancelled transitions', async () => {
    const p = await append(await begin(), '# first');
    for (const slice of [{ index: 0, prefixSHA256: p.prefixSHA256 }, { index: 2, prefixSHA256: p.prefixSHA256 }, { index: 1, prefixSHA256: hash('wrong') }]) await expect(appendDocumentProgram(p, owner, { ...slice, code: '# next', final: false }, 1001)).rejects.toThrow('document_program_sequence_mismatch');
    await expect(appendDocumentProgram(p, owner, {}, 2000)).rejects.toThrow('document_program_closed');
    await expect(append({ ...p, state: 'cancelled' }, '#')).rejects.toThrow('document_program_closed');
  });
  it('counts Unicode points and exact escaped JSON slice bytes', async () => {
    expect((await append(await begin(), '#'.repeat(24000))).slices).toHaveLength(1);
    await expect(append(await begin(), '#'.repeat(24001))).rejects.toThrow('document_program_capacity_exceeded');
    // Exact 24 KiB JSON boundaries, including supplementary Unicode and escapes.
    for (const code of ['界'.repeat(8191) + '#', '🙂'.repeat(6143) + '##', '\u0001'.repeat(4095) + '🙂', ...['\n', '"', '\\'].map(c => c.repeat(12287))]) {
      expect(Buffer.byteLength(JSON.stringify(code))).toBe(24576);
      expect((await append(await begin(), code)).slices[0].code).toBe(code);
      await expect(append(await begin(), code + '#')).rejects.toThrow('document_program_capacity_exceeded');
    }
    await expect(append(await begin(), '界'.repeat(8191) + 'é')).rejects.toThrow('document_program_capacity_exceeded');
  });
  it('allows unfinished whitespace prefixes but never seals a blank build/final', async () => {
    const p = await beginDocumentProgram(owner, { ...prep, stage: 'final', path: 'synthetic.md' }, 2000, 1000);
    const prefix = await append(p, ' \n');
    expect(prefix.slices[0].code).toBe(' \n');
    await expect(append(prefix, ' ', true)).rejects.toThrow();
    expect(documentProgramInvocation(await append(prefix, '# complete', true), owner, 1001).code).toBe(' \n# complete');
  });
  it('enforces total 64K points, total 74KB invocation JSON, and 32 slices', async () => {
    let p = await begin(); for (let n = 0; n < 10; n++) p = await append(p, '#'.repeat(6000)); p = await append(p, '#'.repeat(4000));
    await expect(append(p, '#', true)).rejects.toThrow('document_program_capacity_exceeded');
    expect(documentProgramInvocation(await appendDocumentProgram({ ...p, slices: p.slices.slice(0, -1), prefixSHA256: p.slices.at(-2)!.prefixSHA256 }, owner, { index: 10, prefixSHA256: p.slices.at(-2)!.prefixSHA256, code: '#'.repeat(4000), final: true }, 1001), owner, 1001).code.length).toBe(64000);
    p = await begin(); for (let n = 0; n < 32; n++) p = await append(p, '#');
    await expect(append(p, '#')).rejects.toThrow('document_program_capacity_exceeded');
    const { authoring: _, ...descriptor } = prep;
    const overhead = new TextEncoder().encode(JSON.stringify({ ...descriptor, code: '' })).length;
    let code = '界'.repeat(Math.floor((74000 - overhead) / 3)); code += '#'.repeat(74000 - overhead - new TextEncoder().encode(code).length);
    p = await begin(); for (let n = 0; n < code.length; n += 5000) p = await append(p, code.slice(n, n + 5000));
    expect(new TextEncoder().encode(JSON.stringify(documentProgramInvocation({ ...p, state: 'sealed', slices: p.slices.map((s, i) => ({ ...s, final: i === p.slices.length - 1 })) }, owner, 1001))).length).toBe(74000);
    await expect(append(p, '#')).rejects.toThrow('document_program_capacity_exceeded');
  });
});

function actorFixture() {
  const db = new DatabaseSync(':memory:'); databases.push(db);
  const sql = { exec(query: string, ...values: (string | number | null)[]) {
    const statement = db.prepare(query), rows = statement.columns().length ? statement.all(...values) : (statement.run(...values), []);
    return { toArray: () => rows, one: () => { if (rows.length !== 1) throw new Error('Expected one SQL row'); return rows[0]; }, [Symbol.iterator]: () => rows[Symbol.iterator]() };
  } };
  const network = vi.fn(async () => { throw new Error('No external execution allowed'); }); vi.stubGlobal('fetch', network);
  const actor = new KnotShellConversation({ storage: { sql, transactionSync: (f: () => unknown) => { db.exec('BEGIN'); try { const result = f(); db.exec('COMMIT'); return result; } catch (error) { db.exec('ROLLBACK'); throw error; } }, getAlarm: async () => null, setAlarm: async () => undefined } } as never, { DO: { fetch: network }, SIDECAR_TOKEN_WHISPER: 'synthetic-only' });
  const workflow: ShellWorkflow = { rootID: owner.rootID, sourceMessageID: owner.sourceMessageID, originalRequest: 'Create a PDF guide', mode: 'Create', documentTask: true, documentPipeline: 'agent_v2', documentPolicy: 'author_v1', memoryRead: true, indexRead: true, workspaceInspected: true, documentSkillCommand: documentSkillReadCommand, skills: [documentSkillReadCommand], commands: 4, memoryWritten: false };
  const parent = { proposal: { id: owner.parentID, bot: owner.bot, conversationID: owner.conversationID, title: 'Read complete reference', tool: 'session_input', command: 'cat -- reference.md', timeoutMs: 120000, expiresAt: Date.now() + 600000 }, workspace: owner.workspace, phase: 'finished', logFinal: true, cancelled: false, operation: 'workspace_read', workflow, result: { proposalID: owner.parentID, bot: owner.bot, conversationID: owner.conversationID, status: 'completed', exitCode: 0, terminationConfirmed: true, outputComplete: true, truncated: false, stdout: 'Entire reference', stderr: '', reason: '' } };
  const save = (record = parent) => sql.exec('INSERT OR REPLACE INTO shell_records VALUES (?,?)', owner.parentID, JSON.stringify(record)); save();
  const post = (path: string, body: unknown) => actor.fetch(new Request('https://internal/' + path, { method: 'POST', body: JSON.stringify(body) }));
  const start = async (preparation: unknown = prep) => { const response = await post('document-program/begin', { owner, preparation, expiresAt: Date.now() + 200000 }); expect(response.status).toBe(200); return await response.json() as ReturnType<typeof documentProgramReceipt>; };
  const slice = (p: ReturnType<typeof documentProgramReceipt>, code = '# synthetic', final = false) => post('document-program/append', { owner, id: p.id, slice: { index: p.count, prefixSHA256: p.prefixSHA256, code, final } });
  const propose = (p: ReturnType<typeof documentProgramReceipt>, invocation: DocumentInvocation) => post('propose', { workspace: owner.workspace, workflow: { ...workflow, parentID: owner.parentID }, proposal: { id: id(8), bot: owner.bot, conversationID: owner.conversationID, title: 'Complete source', tool: 'document_script', command: documentInvocationCommand(invocation), documentInvocation: invocation, documentProgramID: p.id, timeoutMs: 120000, expiresAt: Date.now() + 600000 } });
  const stored = (p: ReturnType<typeof documentProgramReceipt>) => JSON.parse(String(sql.exec('SELECT data FROM document_programs WHERE id=?', p.id).toArray()[0]?.data)) as DocumentProgram;
  return { db, sql, actor, network, parent, workflow, save, post, start, slice, propose, stored };
}

describe('document programs in the actual SQLite-backed actor', () => {
  it('reads the indexed game skill when the original playable ask explicitly rejects a guide', () => {
    const request = 'Build and deliver a small playable Pokémon-style battle game as a self-contained HTML file, using original creature names and simple original artwork. Include a player creature, an opponent, visible health, attack choices, turn feedback, a win/loss state and restart. It must actually respond to the controls, not be a guide or source-only description.';
    const index = '## Games (principles only)\n- **games-web** (web-games) — framework choice for browser games.\n';
    expect(slicedHTMLArtifact({ mode: 'Create', originalRequest: request, documentTask: false, artifactFormat: 'html' })).toBe(true);
    expect(indexedHTMLGameSkill(index, request)).toBe('cat /opt/knot-skills/games-web/SKILL.md');
    for (const explanatory of ['Write a PDF guide about games', 'Create a report about RPG combat', 'Explain how browser games work']) expect(indexedHTMLGameSkill(index, explanatory)).toBeUndefined();
    expect(indexedHTMLGameSkill('- **games-design** — balancing', request)).toBeUndefined();
    expect(indexedHTMLGameSkill(index + '- other/games-web/SKILL.md\n', request)).toBeUndefined();
  });
  it('admits sliced explicit HTML game transport without reclassifying it as a document', async () => {
    const f = actorFixture();
    Object.assign(f.workflow, { originalRequest: 'Build a playable monster battle game as a self-contained HTML file', documentTask: false, artifactFormat: 'html', skills: ['cat /opt/knot-skills/games-web/SKILL.md'] });
    delete f.workflow.documentSkillCommand; f.save();
    const descriptor = { ...prep, stage: 'final', title: 'Monster Battle' };
    const p = await f.start(descriptor);
    expect((await f.slice(p, '# complete synthetic HTML writer', true)).status).toBe(200);
    const response = await f.propose(p, documentProgramInvocation(f.stored(p), owner, Date.now()));
    expect(response.status).toBe(200); expect(f.stored(p).state).toBe('claimed');
    const saved = JSON.parse(String(f.sql.exec('SELECT data FROM shell_records WHERE id=?', id(8)).toArray()[0].data));
    expect(saved.workflow).toMatchObject({ documentTask: false, artifactFormat: 'html' });
    expect(saved.workflow.documentFormat).toBeUndefined(); expect(saved.workflow.documentProof).toBeUndefined();
    expect(saved.proposal.documentInvocation).toMatchObject({ stage: 'final', path: 'synthetic.html' });
    expect(f.network).not.toHaveBeenCalled();
  });
  it.each(['source', 'build', 'existing', 'wrong-format', 'no-skill', 'stopped'] as const)('refuses unsafe general HTML program scope: %s', async scenario => {
    const f = actorFixture();
    Object.assign(f.workflow, { originalRequest: 'Build a playable monster battle game as a self-contained HTML file', documentTask: false, artifactFormat: 'html', skills: scenario === 'no-skill' ? [] : ['cat /opt/knot-skills/games-web/SKILL.md'] });
    delete f.workflow.documentSkillCommand; f.save();
    if (scenario === 'stopped') await f.post('activity', { bot: owner.bot, conversationID: owner.conversationID, taskID: owner.rootID, requestID: id(77), sequence: 1, kind: 'cancelled' });
    const descriptor = { ...prep, stage: ['source', 'build', 'existing'].includes(scenario) ? scenario : 'final', path: scenario === 'wrong-format' ? 'synthetic.md' : scenario === 'build' ? 'synthetic.pdf' : 'synthetic.html' };
    expect((await f.post('document-program/begin', { owner, preparation: descriptor, expiresAt: Date.now() + 200000 })).status).toBe(409);
    expect(f.sql.exec('SELECT id FROM document_programs').toArray()).toHaveLength(0); expect(f.network).not.toHaveBeenCalled();
  });
  it('accepts immutable slices without creating shell work, then independently claims exact bytes', async () => {
    const f = actorFixture(), p = await f.start();
    const response = await f.slice(p, '# synthetic 🙂\n', true); expect(response.status).toBe(200);
    const sealed = await response.json() as typeof p;
    expect(f.sql.exec('SELECT id FROM shell_records').toArray()).toHaveLength(1);
    expect((await f.propose(sealed, documentProgramInvocation(f.stored(p), owner, Date.now()))).status).toBe(200);
    expect(f.stored(p).state).toBe('claimed');
    expect(f.sql.exec('SELECT id FROM shell_records').toArray()).toHaveLength(2);
    expect(f.network).not.toHaveBeenCalled();
  });
  it.each(['unsealed', 'changed', 'wrong-root', 'wrong-workspace', 'wrong-parent', 'stopped', 'deleted'] as const)('rejects unsafe admission: %s', async scenario => {
    const f = actorFixture(), p = await f.start();
    if (scenario !== 'unsealed') expect((await f.slice(p, '# synthetic', true)).status).toBe(200);
    let invocation: DocumentInvocation = { stage: prep.stage, interpreter: prep.interpreter, path: prep.path, title: '', deliveryLabel: '', code: scenario === 'changed' ? '# changed' : '# synthetic' };
    if (scenario === 'wrong-root' || scenario === 'wrong-workspace' || scenario === 'wrong-parent') {
      const program = f.stored(p); program.owner[scenario === 'wrong-root' ? 'rootID' : scenario === 'wrong-workspace' ? 'workspace' : 'parentID'] = scenario === 'wrong-workspace' ? 'whisper-' + 'b'.repeat(48) : id(99);
      f.sql.exec('UPDATE document_programs SET data=? WHERE id=?', JSON.stringify(program), p.id);
    }
    if (scenario === 'stopped') await f.post('activity', { bot: owner.bot, conversationID: owner.conversationID, taskID: owner.rootID, requestID: id(77), sequence: 1, kind: 'cancelled' });
    if (scenario === 'deleted') await f.post('documents/erase-conversation', { conversationID: owner.conversationID });
    expect((await f.propose(p, invocation)).status).toBeGreaterThanOrEqual(400);
    expect(f.sql.exec('SELECT id FROM shell_records').toArray()).toHaveLength(1);
    expect(f.network).not.toHaveBeenCalled();
  });
  it('binds a sealed custom-build selection when the original-build latch substitutes its first proof', async () => {
    const f = actorFixture(), sourceID = id(20), buildID = id(21);
    const source = { path: 'original.html', sha256: 'a'.repeat(64), size: 100, format: 'html' as const }, freshSource = { ...source, path: 'fresh.html' };
    const build: DocumentInvocation = { stage: 'build', interpreter: 'python3', path: 'original.pdf', code: '# synthetic conversion', title: '', deliveryLabel: '' };
    const manifest = { path: build.path, sha256: 'b'.repeat(64), size: 200, format: 'pdf', pages: 1, proofs: [] };
    const execution = { invocation: build, source, sourceProposalID: sourceID };
    const base = { ...f.parent.workflow, documentValidation: 'structural_v2' as const, documentSourceReview: true };
    const save = (recordID: string, invocation: DocumentInvocation, stdout: string, workflow: ShellWorkflow, measured?: typeof source) => {
      const record = { ...f.parent, sessionID: 'synthetic-owned-session', operation: 'work', workflow, proposal: { ...f.parent.proposal, id: recordID, tool: 'document_script', documentInvocation: invocation, command: documentInvocationCommand(invocation, invocation.stage === 'build' ? source : undefined, invocation.stage === 'build') }, result: { ...f.parent.result, proposalID: recordID, sessionID: 'synthetic-owned-session', stdout }, ...(measured ? { documentSourceCheck: { sourceProposalID: recordID, sourceSHA256: measured.sha256, verdict: 'pass', observations: [] } } : {}) };
      f.sql.exec('INSERT OR REPLACE INTO shell_records VALUES (?,?)', recordID, JSON.stringify(record));
    };
    save(sourceID, { stage: 'source', interpreter: 'python3', code: '# synthetic source', path: source.path }, 'KNOT_DOCUMENT_SOURCE_V1 ' + JSON.stringify(source), base, source);
    save(buildID, build, 'KNOT_DOCUMENT_V1 ' + JSON.stringify(manifest), { ...base, parentID: sourceID, documentSource: { source, proposalID: sourceID }, documentExecution: execution });
    save(owner.parentID, { stage: 'source', interpreter: 'python3', code: '# fresh synthetic source', path: freshSource.path }, 'KNOT_DOCUMENT_SOURCE_V1 ' + JSON.stringify(freshSource), { ...base, parentID: buildID, documentSource: { source, proposalID: sourceID }, documentExecution: execution }, freshSource);
    const descriptor = { stage: build.stage, interpreter: build.interpreter, path: 'renamed.pdf', title: '', deliveryLabel: '', authoring: 'author' };
    const opened = await f.post('document-program/begin', { owner, preparation: descriptor, expiresAt: Date.now() + 200000 }); expect(opened.status).toBe(200);
    const p = await opened.json() as ReturnType<typeof documentProgramReceipt>;
    expect((await f.slice(p, build.code, true)).status).toBe(200);
    const invocation = documentProgramInvocation(f.stored(p), owner, Date.now());
    const response = await f.post('propose', { workspace: owner.workspace, workflow: { ...base, parentID: owner.parentID }, proposal: { id: id(8), bot: owner.bot, conversationID: owner.conversationID, title: 'Renamed selection', tool: 'document_script', documentInvocation: invocation, documentProgramID: p.id, command: documentInvocationCommand(invocation, freshSource, true), timeoutMs: 120000, expiresAt: Date.now() + 600000 } });
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ tool: 'session_input', documentProgramID: p.id });
    expect(f.stored(p).state).toBe('claimed');
    const saved = JSON.parse(String(f.sql.exec('SELECT data FROM shell_records WHERE id=?', id(8)).toArray()[0].data));
    expect(saved.workflow.documentProof).toMatchObject({ sourceProposalID: buildID, manifest });
    expect(saved.proposal.documentInvocation).toBeUndefined(); expect(f.network).not.toHaveBeenCalled();
  });
  it('uses compare-and-set for racing appends; neither duplicate can replace a prefix', async () => {
    const f = actorFixture(), p = await f.start();
    const results = await Promise.all([f.slice(p, '# left'), f.slice(p, '# right')]);
    expect(results.map(r => r.status).sort()).toEqual([200, 409]);
    expect(f.stored(p).slices).toHaveLength(1); expect(['# left', '# right']).toContain(f.stored(p).slices[0].code);
    expect((await f.slice(p, '# replay')).status).toBe(409);
    expect(f.network).not.toHaveBeenCalled();
  });
  it.each(['begin', 'append', 'seal'] as const)('Stop wins during an in-flight digest: %s', async scenario => {
    const f = actorFixture(), p = scenario === 'begin' ? undefined : await f.start();
    const original = crypto.subtle.digest.bind(crypto.subtle);
    let release!: () => void, entered!: () => void;
    const blocked = new Promise<void>(resolve => { release = resolve; }), observed = new Promise<void>(resolve => { entered = resolve; });
    vi.spyOn(crypto.subtle, 'digest').mockImplementation(async (...args) => { entered(); await blocked; return original(...args); });
    const inFlight = p ? f.slice(p, '# never execute', scenario === 'seal') : f.post('document-program/begin', { owner, preparation: prep, expiresAt: Date.now() + 200000 });
    await observed;
    expect((await f.post('activity', { bot: owner.bot, conversationID: owner.conversationID, taskID: owner.rootID, requestID: id(77), sequence: 1, kind: 'cancelled' })).status).toBe(200);
    release(); expect((await inFlight).status).toBe(409);
    expect(f.sql.exec('SELECT id FROM shell_records').toArray()).toHaveLength(1);
    expect(f.network).not.toHaveBeenCalled();
  });
  it.each(['stopped', 'missing-memory', 'incomplete', 'failed', 'cancelled', 'wrong-source'] as const)('refuses to open an unsafe owned scope: %s', async scenario => {
    const f = actorFixture();
    if (scenario === 'stopped') await f.post('activity', { bot: owner.bot, conversationID: owner.conversationID, taskID: owner.rootID, requestID: id(77), sequence: 1, kind: 'cancelled' });
    if (scenario === 'missing-memory') f.save({ ...f.parent, workflow: { ...f.parent.workflow, memoryRead: false } });
    if (scenario === 'incomplete') f.save({ ...f.parent, result: { ...f.parent.result, outputComplete: false } });
    if (scenario === 'failed') f.save({ ...f.parent, result: { ...f.parent.result, status: 'failed', exitCode: 1 } });
    if (scenario === 'cancelled') f.save({ ...f.parent, cancelled: true });
    expect((await f.post('document-program/begin', { owner: scenario === 'wrong-source' ? { ...owner, sourceMessageID: id(99) } : owner, preparation: prep, expiresAt: Date.now() + 200000 })).status).toBe(409);
    expect(f.sql.exec('SELECT id FROM document_programs').toArray()).toHaveLength(0); expect(f.network).not.toHaveBeenCalled();
  });
  it('keeps cancelled/expired scopes closed and prunes retired-owner data without adoption', async () => {
    const f = actorFixture(), p = await f.start();
    expect((await f.slice(p)).status).toBe(200);
    const old = f.stored(p); old.expiresAt = Date.now() - 1;
    f.sql.exec('UPDATE document_programs SET data=? WHERE id=?', JSON.stringify(old), p.id);
    expect((await f.post('document-program/begin', { owner, preparation: prep, expiresAt: Date.now() + 200000 })).status).toBe(409);
    expect(f.stored(p)).toMatchObject({ state: 'cancelled', slices: old.slices, prefixSHA256: old.prefixSHA256 });
    expect((await f.slice(p, '# cannot resume', true)).status).toBe(409);
    expect(() => documentProgramInvocation(f.stored(p), owner, Date.now())).toThrow('document_program_closed');
    // A genuinely new parent is not a resume or adoption of an expired scope.
    const newOwner = { ...owner, parentID: id(98) };
    f.sql.exec('DELETE FROM shell_records WHERE id=?', owner.parentID);
    f.sql.exec('INSERT INTO shell_records VALUES (?,?)', newOwner.parentID, JSON.stringify({ ...f.parent, proposal: { ...f.parent.proposal, id: newOwner.parentID } }));
    const response = await f.post('document-program/begin', { owner: newOwner, preparation: prep, expiresAt: Date.now() + 200000 });
    expect(response.status).toBe(200); expect(f.sql.exec('SELECT id FROM document_programs WHERE id=?', p.id).toArray()).toHaveLength(0);
    expect(f.network).not.toHaveBeenCalled();
  });
  it('retains a received response after execution expiry without reopening, appending or executing it', async () => {
    const f = actorFixture(), p = await f.start();
    const old = f.stored(p); old.expiresAt = Date.now() - 1;
    f.sql.exec('UPDATE document_programs SET data=? WHERE id=?', JSON.stringify(old), p.id);
    const content = '{"code":"unfinished';
    const schema = { type: 'object' }, schemaHash = hash(JSON.stringify(schema));
    const response = await f.post('document-program/reject', { owner, id: p.id, record: {
      version: 'document_author_rejection_v1', response: { content, complete: false, envelope: {} },
      context: { version: 'document_author_replay_v1', preparation: old.preparation, prefix: '', index: 0 },
      schema, schemaHash, diagnostic: { branch: 'stream_eof', fieldPath: '$.content', expectedShape: 'complete_json_object', receivedShape: 'incomplete_json', unexplained: false }, rejectedBodySHA256: hash(content),
    } });
    expect(response.status).toBe(200);
    expect(f.sql.exec('SELECT id FROM document_author_rejections WHERE id=?', p.id).toArray()).toHaveLength(1);
    expect(f.stored(p)).toEqual(old);
    expect((await f.slice(p, '# not a resume', true)).status).toBe(409);
    expect(() => documentProgramInvocation(old, owner, Date.now())).toThrow('document_program_closed');
    expect(f.network).not.toHaveBeenCalled();
  });
  it('erasure wins against an in-flight final append and removes its stored bytes', async () => {
    const f = actorFixture(), p = await f.start(), original = crypto.subtle.digest.bind(crypto.subtle);
    let release!: () => void, entered!: () => void;
    const blocked = new Promise<void>(r => { release = r; }), observed = new Promise<void>(r => { entered = r; });
    vi.spyOn(crypto.subtle, 'digest').mockImplementation(async (...args) => { entered(); await blocked; return original(...args); });
    const inFlight = f.slice(p, '# private synthetic content', true); await observed;
    expect((await f.post('documents/erase-conversation', { conversationID: owner.conversationID })).status).toBe(200);
    release(); expect((await inFlight).status).toBe(409);
    expect(f.sql.exec('SELECT id FROM document_programs').toArray()).toHaveLength(0); expect(f.network).not.toHaveBeenCalled();
  });
  it('accepts complete retained whole reads but rejects boundary records lacking a real command receipt', async () => {
    const f = actorFixture();
    f.save({ ...f.parent, wholeRead: true, result: { ...f.parent.result, contextTruncated: true } } as typeof f.parent);
    await f.start();
    const g = actorFixture(); g.save({ ...g.parent, boundary: { id: 'synthetic-boundary' } } as typeof g.parent);
    expect((await g.post('document-program/begin', { owner, preparation: prep, expiresAt: Date.now() + 200000 })).status).toBe(409);
  });
});
