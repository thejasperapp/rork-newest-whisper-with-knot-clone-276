// @vitest-environment node
// Real actor admission with synthetic durable storage/receipts. No executor,
// utility, generated command, model, file capture or external service runs.
import { afterEach, describe, expect, it, vi } from 'vitest';
vi.mock('cloudflare:workers', () => ({ DurableObject: class { constructor(protected ctx: unknown, protected env: unknown) {} } }));
import { knotShellRoute, KnotShellConversation, type KnotShellProposal, type ShellWorkflow, type ShellResult, type ShellEvidence } from '../../functions/knot-shell';
import { documentInvocationCommand, verifiedDocumentExecution, type DocumentInvocation, type DocumentSource } from '../../functions/knot-document-build';
import { documentProofCommand, documentSkillReadCommand, verifiedDocumentProof } from '../../functions/knot-document-proof';
import { requestedDocumentFormat } from '../../functions/knot-document-format';
import { documentManifest } from '../../functions/knot-documents';
import { knotDocV2SHA256, residentDocumentTransport } from '../../functions/knot-document-resident';
import { shellCommandLimit } from '../../functions/knot-work-budget';
import { structuredSourceCode, type StructuredDocument } from '../../functions/knot-document-structured';
import { rawContentCode } from '../../functions/knot-document-raw-content';
import { skillDraftCommand } from '../../functions/knot-skill-drafts';
import { validateDocumentReviewResume, validateDocumentAdvisoryCapture } from '../../functions/knot-document-review-resume';

const id = (n: number) => '00000000-0000-4000-8000-' + n.toString().padStart(12, '0');
const rootID = id(1), conversationID = id(2), sourceID = id(3), buildID = id(4), freshID = id(5), proposalID = id(6), proofID = id(7);
const workspace = 'whisper-' + 'a'.repeat(48);
type Stored = { proposal: KnotShellProposal; workspace: string; phase: string; cancelled: boolean; logFinal?: boolean; sessionID?: string; finishedAt?: number; workflow: ShellWorkflow; result: ShellResult; operation: string; nextProposalID?: string; documentSourceCheck?: unknown; documentContentFinding?: unknown; documentReviewResume?: unknown; documentAdvisoryCapture?: unknown; documentAssessment?: unknown };
function fixture(quality = false, measuredSource?: DocumentSource, measuredFinal?: { sha256: string; size: number }) {
  const records = new Map<string, Stored>(), events: Record<string, unknown>[] = [], captured: Record<string, unknown>[] = [];
  const sql = { exec: (query: string, ...args: unknown[]) => {
    let rows: unknown[] = [];
    if (query.startsWith('CREATE TABLE')) { /* synthetic schema boundary */ }
    else if (query === 'SELECT data FROM shell_records') rows = [...records.values()].map(record => ({ data: JSON.stringify(record) }));
    else if (query === 'SELECT data FROM shell_records WHERE id = ?') rows = records.has(String(args[0])) ? [{ data: JSON.stringify(records.get(String(args[0]))) }] : [];
    else if (query === 'INSERT OR REPLACE INTO shell_records VALUES (?, ?)') records.set(String(args[0]), JSON.parse(String(args[1])));
    else if (query.startsWith('INSERT INTO shell_events')) events.push(JSON.parse(String(args[3])));
    else if (query === 'SELECT data FROM shell_events WHERE seq = ? AND proposal_id = ? AND bot = ? AND conversation_id = ?') rows = events.filter(event => event.sequence === args[0] && event.proposalID === args[1]).map(event => ({ data: JSON.stringify(event) }));
    else if (query === 'SELECT data FROM knot_documents WHERE bot = ? AND conversation_id = ? ORDER BY expires,id') rows = captured.map(document => ({ data: JSON.stringify(document) }));
    else if (query === 'SELECT data FROM knot_documents WHERE id = ?') rows = [];
    else if (query === 'SELECT id FROM knot_documents WHERE expires <= ? AND bytes > 0' || query === 'SELECT 1 FROM knot_documents WHERE bytes > 0 LIMIT 1' || query === "SELECT 1 FROM knot_document_deletions WHERE conversation_id IN (?, '*')" || query === 'SELECT 1 FROM document_program_stops WHERE root_id=? AND bot=? AND conversation_id=?') rows = [];
    else throw new Error('Unexpected synthetic SQL: ' + query);
    return { toArray: () => rows };
  } };
  const network = vi.fn(async () => { throw new Error('No external execution permitted'); });
  vi.stubGlobal('fetch', network);
  const actor = new KnotShellConversation({ storage: { sql, transactionSync: (f: () => unknown) => f(), getAlarm: async () => null, setAlarm: async () => undefined } } as never, { DO: { fetch: network }, SIDECAR_TOKEN_WHISPER: 'synthetic-only', EXPO_PUBLIC_TOOLKIT_URL: 'https://checker-dead.invalid', EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY: 'synthetic-only' });
  const source: DocumentSource = measuredSource ?? { path: 'recipes.html', sha256: 'a'.repeat(64), size: 1877, format: 'html' };
  const freshSource = { ...source, path: 'recipes-v2.html' };
  const resident = residentDocumentTransport('2.0.0', rootID)!;
  const invocation: DocumentInvocation = { stage: 'build', interpreter: 'knot-doc', code: '', path: 'recipes.pdf' };
  const manifest = { path: invocation.path, sha256: 'b'.repeat(64), size: 10616, ...measuredFinal, format: 'pdf' as const, pages: 1, proofs: [] };
  const execution = { invocation, source, sourceProposalID: sourceID, resident };
  const base: ShellWorkflow = { ...(quality ? { documentQuality: 'quality_v1' as const } : {}), rootID, originalRequest: 'Create a designed PDF of fat-loss recipes', sourceMessageID: id(9), mode: 'Create', documentTask: true, documentFormat: requestedDocumentFormat('Create a PDF of fat-loss recipes'), documentValidation: 'structural_v2', documentSourceReview: true, documentPolicy: 'author_v1', documentPipeline: 'agent_v2', residentDocumentTool: '2.0.0', documentSkillCommand: documentSkillReadCommand, memoryRead: true, indexRead: true, workspaceInspected: true, skills: [documentSkillReadCommand], commands: 5, memoryWritten: false };
  const save = (recordID: string, value: DocumentInvocation | undefined, command: string, stdout: string, workflow: ShellWorkflow) => {
    const proposal = { id: recordID, bot: 'main' as const, conversationID, title: 'Synthetic original work', tool: value ? 'document_script' : 'session_input', command, timeoutMs: 120000, expiresAt: Date.now() + 600000, documentInvocation: value };
    const result: ShellResult = { proposalID: recordID, bot: 'main', conversationID, status: 'completed', stdout, stderr: '', exitCode: 0, outputComplete: true, terminationConfirmed: true, truncated: false, reason: '', sessionID: 'synthetic-owned-session' };
    const record: Stored = { proposal, workspace, phase: 'finished', cancelled: false, logFinal: true, sessionID: result.sessionID, finishedAt: Date.now(), workflow, result, operation: 'work' };
    if (value?.stage === 'source') record.documentSourceCheck = { sourceProposalID: recordID, sourceSHA256: source.sha256, verdict: 'pass', observations: [] };
    records.set(recordID, structuredClone(record)); return records.get(recordID)!;
  };
  const sourceInvocation: DocumentInvocation = { stage: 'source', interpreter: 'python3', code: '# Never executed', path: source.path };
  save(sourceID, sourceInvocation, documentInvocationCommand(sourceInvocation), 'KNOT_DOCUMENT_SOURCE_V1 ' + JSON.stringify(source), base);
  const audit = { version: resident.version, toolSHA256: knotDocV2SHA256, inputs: { toolVersion: '2.0.0', sourceSHA256: source.sha256, sourceBytes: source.size, sourceFormat: 'html', design: 'author-v1', houseStyleSHA256: 'f'.repeat(64) }, manifest: { ...manifest, toolVersion: '2.0.0', taskID: rootID, sourceSHA256: source.sha256, inputsSHA256: 'c'.repeat(64), proofStageOnly: true, independentVerification: false } };
  save(buildID, invocation, documentInvocationCommand(invocation, source, true, resident), 'KNOT_RESIDENT_DOCUMENT_V1 ' + JSON.stringify(audit) + '\nKNOT_DOCUMENT_V1 ' + JSON.stringify(manifest), { ...base, commands: 6, parentID: sourceID, documentSource: { source, proposalID: sourceID }, documentExecution: execution });
  const freshInvocation = { ...sourceInvocation, path: freshSource.path };
  save(freshID, freshInvocation, documentInvocationCommand(freshInvocation), 'KNOT_DOCUMENT_SOURCE_V1 ' + JSON.stringify(freshSource), { ...base, commands: 8, parentID: buildID, documentSource: { source, proposalID: sourceID }, documentExecution: execution });
  const nextInvocation = { ...invocation, path: 'recipes-v2.pdf' };
  const proposal: KnotShellProposal = { id: proposalID, bot: 'main', conversationID, tool: 'document_script', title: 'Redundant build selection', command: documentInvocationCommand(nextInvocation, freshSource, true, resident), timeoutMs: 120000, expiresAt: Date.now() + 600000, documentInvocation: nextInvocation };
  const propose = (signal?: AbortSignal, changes: Partial<KnotShellProposal> = {}) => actor.fetch(new Request('https://internal/propose', { method: 'POST', body: JSON.stringify({ proposal: { ...proposal, ...changes }, workspace, workflow: { ...base, parentID: freshID } }), signal }));
  const proofManifest = () => ({ ...manifest, proofs: [{ path: 'deliverables/knot-proof-' + buildID + '/page-1.png', page: 1, sha256: 'd'.repeat(64), sourceSHA256: manifest.sha256 }], verification: { ...(quality ? { allPageProofs: true } : {}), version: 'knot_document_proof_v1', sourceSHA256: manifest.sha256, sourceSize: manifest.size, format: 'pdf', renderedPages: 1, textSHA256: 'e'.repeat(64), markupScan: 'clear', renderer: 'poppler', producerChecked: false, structureChecked: true, textPath: 'deliverables/knot-proof-' + buildID + '/text.txt', textSize: 100 } });
  const addProof = (valid = true) => {
    save(proofID, undefined, documentProofCommand(manifest, buildID, true, true, quality), valid ? 'KNOT_DOCUMENT_V1 ' + JSON.stringify(proofManifest()) : 'No valid proof recorded', { ...base, commands: 7, parentID: buildID, documentSource: { source, proposalID: sourceID }, documentExecution: execution, documentProof: { manifest, sourceProposalID: buildID } });
    records.get(freshID)!.workflow.parentID = proofID;
  };
  const receipt = (recordID: string) => actor.fetch(new Request('https://internal/receipt', { method: 'POST', body: JSON.stringify({ bot: 'main', conversationID, proposalID: recordID }) }));
  return { actor, records, events, captured, network, propose, addProof, proofManifest, receipt, manifest, execution, freshSource };
}
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });
describe('first-pass layout actor admission', () => {
  it.each([true, false])('requires receipt-bound initial-layout authorization: %s', async enabled => {
    const f = fixture();
    f.records.delete(sourceID); f.records.delete(buildID);
    const parent = f.records.get(freshID)!;
    delete parent.workflow.parentID; delete parent.workflow.documentSource; delete parent.workflow.documentExecution;
    parent.workflow.documentContentRenderer = 'content_v1';
    Object.assign(parent.workflow, enabled ? { documentInitialLayout: 'section_v2' } : {});
    parent.proposal.documentInvocation = undefined; parent.proposal.command = 'find . -maxdepth 4 -type f'; parent.operation = 'workspace_inventory'; parent.result.stdout = './MEMORY.md';
    const document: StructuredDocument = { title: 'Reading plan', subtitle: '', sections: [{ id: 'prep', title: 'Prepare', blocks: [{ kind: 'paragraph', text: 'Arrange a comfortable chair.' }] }, { id: 'schedule', title: 'Weekend', blocks: [{ kind: 'paragraph', text: 'Friday, Saturday and Sunday.' }] }] };
    const invocation: DocumentInvocation = { stage: 'source', interpreter: 'python3', path: 'fresh-reading.html', code: structuredSourceCode({ version: 'content_v1', document, layout: { schedule: 'new_page' }, patched: false }, 'fresh-reading.html') };
    const response = await f.propose(undefined, { documentInvocation: invocation, command: documentInvocationCommand(invocation) });
    const result = await response.json();
    expect(response.status, JSON.stringify(result)).toBe(enabled ? 200 : 409);
    if (!enabled) expect(result).toMatchObject({ error: 'document_authoring_required' });
    else expect(f.records.get(proposalID)?.proposal.documentInvocation).toEqual(invocation);
    expect(f.network).not.toHaveBeenCalled();
  });
});
describe('explicit public advisory routing', () => {
  it.each(['documents/capture-advisory', 'documents'] as const)('dispatches capture_advisory to its own actor path: %s', async path => {
    const forwarded: Request[] = [];
    const env = { SUPABASE_SERVICE_ROLE_KEY: 'synthetic-only', SIDECAR_TOKEN_WHISPER: 'synthetic-only', DO: { fetch: async (request: Request) => { forwarded.push(request); return new Response('{}'); } } };
    await knotShellRoute(new Request('https://example.invalid/knot/shell/' + path, { method: 'POST', body: JSON.stringify({ action: 'capture_advisory', bot: 'main', conversationID, proposalID: proofID }) }), env as never, id(90));
    expect(forwarded).toHaveLength(1);
    expect(new URL(forwarded[0].url).pathname).toBe('/documents/capture-advisory');
    expect(forwarded[0].headers.get('X-Knot-Worker-Build')).toMatch(/^[a-f0-9]{64}$/);
    expect(forwarded[0].headers.get('X-Knot-Request-ID')).toMatch(/^[a-f0-9-]{36}$/);
    expect(await forwarded[0].json()).toMatchObject({ action: 'capture_advisory', proposalID: proofID });
  });
  it('rejects retrieval actions on the capture-only route without dispatch', async () => {
    const dispatch = vi.fn();
    const response = await knotShellRoute(new Request('https://example.invalid/knot/shell/documents/capture-advisory', { method: 'POST', body: JSON.stringify({ action: 'file', bot: 'main', conversationID, proposalID: proofID }) }), { DO: { fetch: dispatch } } as never, id(90));
    expect(response.status).toBe(400); expect(dispatch).not.toHaveBeenCalled();
  });
});
describe('explicit exact-final review-only continuation', () => {
  const authorization = () => ({ version: 'knot_document_review_resume_v1', id: id(80), taskID: rootID, sourceMessageID: id(9), sourceProposalID: sourceID, buildProposalID: buildID, finalSHA256: 'b'.repeat(64), finalSize: 10616, pages: 1 });
  const prepare = () => {
    const f = fixture(true); f.addProof(); f.records.delete(freshID);
    f.records.get(proofID)!.documentContentFinding = { proposalID: proofID, issue: 'document_visual_review_unavailable', observations: [] };
    return f;
  };
  it.each(['valid', 'hash', 'size', 'pages', 'task', 'source-message', 'source-id', 'build-id', 'version', 'id', 'finding', 'missing-source', 'missing-build', 'uncertain', 'proof-command'] as const)('binds request, source/build/proof and original finding: %s', async scenario => {
    const f = prepare(), receipt = await (await f.receipt(proofID)).json() as ShellEvidence;
    const request = authorization();
    if (scenario === 'hash') request.finalSHA256 = 'c'.repeat(64);
    if (scenario === 'size') request.finalSize++;
    if (scenario === 'pages') request.pages++;
    if (scenario === 'task') request.taskID = id(99);
    if (scenario === 'source-message') request.sourceMessageID = id(99);
    if (scenario === 'source-id') request.sourceProposalID = id(99);
    if (scenario === 'build-id') request.buildProposalID = id(99);
    if (scenario === 'version') request.version = 'not-authorized';
    if (scenario === 'id') request.id = 'invalid';
    if (scenario === 'finding') receipt.workflow!.documentContentFinding!.issue = 'document_content_incomplete';
    if (scenario === 'missing-source') receipt.evidence = receipt.evidence.filter(item => item.proposalID !== sourceID);
    if (scenario === 'missing-build') receipt.evidence = receipt.evidence.filter(item => item.proposalID !== buildID);
    if (scenario === 'uncertain') receipt.terminationConfirmed = false;
    if (scenario === 'proof-command') receipt.reviewedCommand += '\n# altered';
    const before = JSON.stringify(receipt);
    if (scenario === 'valid') expect(validateDocumentReviewResume(request, receipt).manifest.sha256).toBe(request.finalSHA256);
    else expect(() => validateDocumentReviewResume(request, receipt)).toThrow('document_review_resume_unavailable');
    expect(JSON.stringify(receipt)).toBe(before); expect(f.network).not.toHaveBeenCalled();
  });
  it('persists one-shot intent before review I/O, never replays after lost/unavailable review and preserves historical finding', async () => {
    const f = prepare(), finding = structuredClone(f.records.get(proofID)!.documentContentFinding);
    const send = () => f.actor.fetch(new Request('https://internal/documents', { method: 'POST', body: JSON.stringify({ action: 'resume_review', bot: 'main', conversationID, proposalID: proofID, consentVersion: 'knot_ai_consent_v4', visualReviewAllowed: true, expiresAt: Date.now() + 170000, reviewResume: authorization() }) }));
    expect(await (await send()).json()).toEqual({ issue: 'document_capture_unavailable' });
    expect(f.network).toHaveBeenCalledTimes(1);
    expect(f.records.get(proofID)!.documentReviewResume).toMatchObject({ id: id(80), state: 'started', finalSHA256: 'b'.repeat(64) });
    expect(await (await send()).json()).toEqual({ issue: 'document_review_resume_unconfirmed', newExecution: false });
    expect(f.network).toHaveBeenCalledTimes(1);
    expect(f.records.get(proofID)!.documentContentFinding).toEqual(finding);
    expect(f.events).toContainEqual(expect.objectContaining({ kind: 'document_review_resume_started', newBuildExecution: false }));
  });
  it.each(['no-consent', 'no-visual', 'cancelled', 'descendant', 'source-finding'] as const)('rejects unsafe resumption before I/O: %s', async scenario => {
    const f = prepare();
    if (scenario === 'cancelled') f.records.get(proofID)!.cancelled = true;
    if (scenario === 'descendant') f.records.get(proofID)!.nextProposalID = freshID;
    if (scenario === 'source-finding') f.records.get(sourceID)!.documentSourceCheck = { issue: 'document_content_incomplete' };
    const response = await f.actor.fetch(new Request('https://internal/documents', { method: 'POST', body: JSON.stringify({ action: 'resume_review', bot: 'main', conversationID, proposalID: proofID, consentVersion: scenario === 'no-consent' ? 'knot_ai_consent_v3' : 'knot_ai_consent_v4', visualReviewAllowed: scenario !== 'no-visual', expiresAt: Date.now() + 170000, reviewResume: authorization() }) }));
    expect(await response.json()).not.toHaveProperty('document'); expect(f.network).not.toHaveBeenCalled(); expect(f.records.get(proofID)!.documentReviewResume).toBeUndefined();
  });
});
describe('explicit advisory capture of the unchanged reviewed final', () => {
  const authorization = () => ({ version: 'knot_document_advisory_capture_v1', id: id(81), taskID: rootID, sourceMessageID: id(9), sourceProposalID: sourceID, buildProposalID: buildID, proofProposalID: proofID, finalSHA256: 'b'.repeat(64), finalSize: 10616, pages: 1, reviewResumeID: id(80), eventSequence: 925, noFurtherRepair: true });
  const prepare = () => {
    const f = fixture(true); f.addProof(); f.records.delete(freshID);
    const record = f.records.get(proofID)!;
    record.documentContentFinding = { proposalID: proofID, issue: 'document_visual_review_unavailable', observations: [] };
    record.documentReviewResume = { id: id(80), finalSHA256: 'b'.repeat(64), state: 'finished', issue: 'document_visual_incomplete' };
    f.events.push({ sequence: 925, proposalID: proofID, kind: 'document_visual_blocked', resumeID: id(80), issue: 'document_visual_incomplete', observations: ['Page 1: Nutrition spacing is inconsistent.'] });
    return f;
  };
  const send = (f: ReturnType<typeof prepare>, changes: object = {}) => f.actor.fetch(new Request('https://internal/documents', { method: 'POST', body: JSON.stringify({ action: 'capture_advisory', bot: 'main', conversationID, proposalID: proofID, consentVersion: 'knot_ai_consent_v4', visualReviewAllowed: true, expiresAt: Date.now() + 40000, advisoryCapture: authorization(), ...changes }) }));
  it.each(['valid', 'wrong-proof', 'wrong-hash', 'wrong-resume', 'wrong-source', 'wrong-size', 'wrong-pages', 'wrong-event', 'unbound-finding', 'empty-finding', 'unfinished-review', 'no-approval'] as const)('binds historical observations without manufacturing per-page passes: %s', async scenario => {
    const f = prepare(), receipt = await (await f.receipt(proofID)).json() as ShellEvidence;
    const a = authorization(), e = structuredClone(f.events[0]);
    const resume = f.records.get(proofID)!.documentReviewResume as { id: string; finalSHA256: string; state: 'started' | 'finished'; issue: string };
    if (scenario === 'wrong-proof') a.proofProposalID = id(99);
    if (scenario === 'wrong-hash') a.finalSHA256 = 'c'.repeat(64);
    if (scenario === 'wrong-resume') a.reviewResumeID = id(99);
    if (scenario === 'wrong-source') a.sourceProposalID = id(99);
    if (scenario === 'wrong-size') a.finalSize++;
    if (scenario === 'wrong-pages') a.pages++;
    if (scenario === 'wrong-event') e.kind = 'document_content_blocked';
    if (scenario === 'unbound-finding') e.resumeID = id(99);
    if (scenario === 'empty-finding') e.observations = [];
    if (scenario === 'unfinished-review') resume.state = 'started';
    if (scenario === 'no-approval') a.noFurtherRepair = false;
    if (scenario === 'valid') expect(validateDocumentAdvisoryCapture(a, receipt, resume, e).advisory).toEqual({ finalSHA256: a.finalSHA256, status: 'issues', observations: e.observations, basis: 'retained_event', eventSequence: 925, resumeID: id(80) });
    else expect(() => validateDocumentAdvisoryCapture(a, receipt, resume, e)).toThrow('document_advisory_capture_unavailable');
    expect(f.network).not.toHaveBeenCalled();
  });
  it('read-only capture status returns retained manifest and once-only state without starting work', async () => {
    const f = prepare();
    const response = await f.actor.fetch(new Request('https://internal/documents/capture-status', { method: 'POST', body: JSON.stringify({ bot: 'main', conversationID, proposalID: proofID }) }));
    expect(await response.json()).toMatchObject({ captureHandler: 'capture_advisory', advisoryCapture: null, manifest: { sha256: 'b'.repeat(64), pages: 1 }, reviewResume: { state: 'finished', id: id(80) } });
    expect(f.records.get(proofID)!.documentAdvisoryCapture).toBeUndefined(); expect(f.network).not.toHaveBeenCalled(); expect(f.events).toHaveLength(1);
  });
  it('the dedicated actor route admits capture without a retrieval documentID and stamps durable start evidence', async () => {
    const f = prepare();
    const response = await f.actor.fetch(new Request('https://internal/documents/capture-advisory', { method: 'POST', headers: { 'X-Knot-Request-ID': id(92), 'X-Knot-Worker-Build': 'f'.repeat(64) }, body: JSON.stringify({ action: 'capture_advisory', bot: 'main', conversationID, proposalID: proofID, consentVersion: 'knot_ai_consent_v4', visualReviewAllowed: true, expiresAt: Date.now() + 40000, advisoryCapture: authorization() }) }));
    expect(await response.json()).toEqual({ issue: 'document_capture_unavailable' });
    expect(response.headers.get('X-Knot-Handler')).toBe('capture_advisory');
    expect(response.headers.get('X-Knot-Actor-Build')).toMatch(/^[a-f0-9]{64}$/);
    expect(f.events).toContainEqual(expect.objectContaining({ kind: 'document_advisory_capture_started', handler: 'capture_advisory', requestID: id(92), workerBuildSHA256: 'f'.repeat(64), actorBuildSHA256: expect.stringMatching(/^[a-f0-9]{64}$/) }));
    expect(f.network).toHaveBeenCalledTimes(1);
  });
  it('durably owns capture once, preserves the consumed review and observes duplicates without replay', async () => {
    const f = prepare(), previous = structuredClone(f.records.get(proofID)!);
    expect(await (await send(f)).json()).toEqual({ issue: 'document_capture_unavailable' });
    expect(f.network).toHaveBeenCalledTimes(1);
    expect(f.records.get(proofID)!.documentAdvisoryCapture).toMatchObject({ id: id(81), state: 'started' });
    expect(f.records.get(proofID)!.documentReviewResume).toEqual(previous.documentReviewResume);
    expect(f.records.get(proofID)!.documentContentFinding).toEqual(previous.documentContentFinding);
    expect(await (await send(f)).json()).toEqual({ issue: 'document_advisory_capture_unconfirmed', newExecution: false });
    expect(f.network).toHaveBeenCalledTimes(1);
    expect(f.events).toContainEqual(expect.objectContaining({ kind: 'document_advisory_capture_started', newReview: false, newExecution: false }));
  });
  it('a concurrent duplicate observes durable intent rather than starting competing I/O', async () => {
    const f = prepare(); let release: ((response: Response) => void) | undefined;
    f.network.mockImplementationOnce(() => new Promise<Response>(resolve => { release = resolve; }) as never);
    const pending = send(f); await vi.waitFor(() => expect(release).toBeDefined());
    expect(await (await send(f)).json()).toMatchObject({ issue: 'document_advisory_capture_unconfirmed', newExecution: false });
    release!(new Response('changed bytes')); expect(await (await pending).json()).toMatchObject({ issue: 'document_bytes_changed' });
    expect(f.network).toHaveBeenCalledTimes(1);
  });
  it.each(['no-consent', 'missing-event', 'cancelled', 'descendant', 'wrong-owner', 'source-finding', 'changed-session', 'uncertain-build'] as const)('refuses unsafe capture-only admission before I/O: %s', async scenario => {
    const f = prepare();
    if (scenario === 'missing-event') f.events.length = 0;
    if (scenario === 'cancelled') f.records.get(proofID)!.cancelled = true;
    if (scenario === 'descendant') f.records.get(proofID)!.nextProposalID = freshID;
    if (scenario === 'wrong-owner') f.records.get(buildID)!.workspace = 'unowned';
    if (scenario === 'source-finding') f.records.get(sourceID)!.documentSourceCheck = { issue: 'document_content_incomplete' };
    if (scenario === 'changed-session') f.records.get(sourceID)!.sessionID = 'another-session';
    if (scenario === 'uncertain-build') f.records.get(buildID)!.result.terminationConfirmed = false;
    expect(await (await send(f, scenario === 'no-consent' ? { consentVersion: 'knot_ai_consent_v3' } : {})).json()).not.toHaveProperty('document');
    expect(f.records.get(proofID)!.documentAdvisoryCapture).toBeUndefined(); expect(f.network).not.toHaveBeenCalled();
  });
});
describe('assessed visual repair finalization authority', () => {
  it.each(['read-only', 'new-source', 'uncertain', 'cancelled', 'foreign-workspace', 'changed-session'] as const)('does not select an older assessed artifact after inappropriate descendants: %s', async scenario => {
    const f = fixture(true); f.addProof();
    const proof = f.records.get(proofID)!, descendant = f.records.get(freshID)!;
    proof.nextProposalID = freshID;
    proof.documentAssessment = { binding: 'synthetic', review: 'issues', observations: ['Page 1: Spacing.'] };
    proof.documentContentFinding = { proposalID: proofID, issue: 'document_visual_incomplete', observations: ['Page 1: Spacing.'] };
    if (scenario !== 'new-source') {
      descendant.operation = 'workspace_read'; descendant.proposal.documentInvocation = undefined; descendant.proposal.command = 'cat -- recipes.html';
    }
    if (scenario === 'uncertain') descendant.result.status = 'uncertain';
    if (scenario === 'cancelled') descendant.cancelled = true;
    if (scenario === 'foreign-workspace') descendant.workspace = 'unowned';
    if (scenario === 'changed-session') descendant.sessionID = descendant.result.sessionID = 'another-session';
    const response = await f.actor.fetch(new Request('https://internal/documents/capture', { method: 'POST', body: JSON.stringify({ bot: 'main', conversationID, proposalID: proofID, continuationParentID: freshID, consentVersion: 'knot_ai_consent_v4', visualReviewAllowed: true, repairVisual: false, expiresAt: Date.now() + 40000 }) }));
    expect(await response.json()).toEqual({ issue: scenario === 'read-only' ? 'document_capture_unavailable' : 'document_capture_cancelled' });
    expect(f.network).toHaveBeenCalledTimes(scenario === 'read-only' ? 1 : 0);
  });
});
describe('document-only expanded actor admission', () => {
  it.each(['owned', 'mismatch', 'missing-invocation', 'wrong-tool', 'missing-workflow', 'unowned-parent', 'forged-workflow', 'oversize-invocation'] as const)('retains exact owned authority for a long program: %s', async scenario => {
    const f = fixture();
    const invocation: DocumentInvocation = { stage: 'source', interpreter: 'python3', code: '#'.repeat(64000), path: 'new-complete-source.html', title: '', deliveryLabel: '' };
    const command = documentInvocationCommand(invocation);
    expect(new TextEncoder().encode(command).length).toBeGreaterThan(12000);
    const original = structuredClone([...f.records]);
    const owned = f.records.get(freshID)!.workflow;
    // This fixture already has a measured source: replacement requires a real
    // owned content finding, not merely enough program bytes or a caller flag.
    f.records.get(freshID)!.documentContentFinding = { proposalID: freshID, issue: 'document_content_incomplete', observations: ['The requested recipe explanation is missing.'] };
    if (scenario === 'forged-workflow') owned.documentTask = false;
    const response = await f.actor.fetch(new Request('https://internal/propose', { method: 'POST', body: JSON.stringify({ workspace, proposal: { id: proposalID, bot: 'main', conversationID, tool: scenario === 'wrong-tool' ? 'session_input' : 'document_script', title: 'Complete source', timeoutMs: 120000, expiresAt: Date.now() + 600000, command: scenario === 'mismatch' ? command + '\n# forged suffix' : command, ...(scenario !== 'missing-invocation' ? { documentInvocation: scenario === 'oversize-invocation' ? { ...invocation, code: '#'.repeat(64001) } : invocation } : {}) }, ...(scenario !== 'missing-workflow' ? { workflow: { ...owned, documentTask: true, parentID: scenario === 'unowned-parent' ? id(999) : freshID } } : {}) }) }));
    if (scenario === 'owned') {
      expect(response.status).toBe(200);
      expect(await response.json()).toMatchObject({ tool: 'document_script', command, documentInvocation: invocation });
      expect(f.records.get(proposalID)!.proposal.command).toBe(command);
    } else {
      expect(response.status).toBeGreaterThanOrEqual(400);
      expect(f.records.has(proposalID)).toBe(false);
      if (scenario === 'oversize-invocation') expect(await response.json()).toMatchObject({ fields: ['arguments.code:size'], sizeFacts: { codeCharacters: 64001, codeCharacterLimit: 64000 } });
      // No new execution, source mutation or parent advancement on rejection.
      expect(f.records.get(freshID)?.nextProposalID).toBeUndefined();
      expect(f.records.get(sourceID)!.proposal).toEqual(new Map(original).get(sourceID)!.proposal);
    }
    expect(f.network).not.toHaveBeenCalled();
  });
});
describe('fresh source text writer actor admission', () => {
  it.each(['valid', 'raw-markdown', 'appended-code', 'historical'] as const)('retains source checks and exact writer authority: %s', async scenario => {
    const f = fixture(); f.records.delete(sourceID); f.records.delete(buildID);
    const parent = f.records.get(freshID)!;
    delete parent.workflow.parentID; delete parent.workflow.documentSource; delete parent.workflow.documentExecution;
    if (scenario !== 'historical') parent.workflow.documentSourceAuthoring = 'text_v1';
    parent.proposal.documentInvocation = undefined; parent.proposal.command = 'find . -maxdepth 4 -type f'; parent.operation = 'workspace_inventory'; parent.result.stdout = './MEMORY.md';
    const path = 'garden.md';
    const code = scenario === 'raw-markdown' ? '# Garden\nMint is invasive.' : scenario === 'historical' ? '# Historical exact source code\n' : rawContentCode({ version: 'raw_content_v1', content: '# Garden\nMint is invasive.' }, path) + (scenario === 'appended-code' ? '\nprint("extra")\n' : '');
    const invocation: DocumentInvocation = { stage: 'source', interpreter: 'python3', path, code };
    const response = await f.propose(undefined, { documentInvocation: invocation, command: documentInvocationCommand(invocation) });
    const result = await response.json(), accepted = ['valid', 'historical'].includes(scenario);
    expect(response.status, JSON.stringify(result)).toBe(accepted ? 200 : 409);
    if (accepted) expect(f.records.get(proposalID)?.proposal.documentInvocation).toEqual(invocation);
    else { expect(result).toMatchObject({ error: 'document_authoring_required' }); expect(f.records.has(proposalID)).toBe(false); }
    expect(f.network).not.toHaveBeenCalled();
  });
});
describe('fresh raw data writer actor admission', () => {
  it.each(['valid', 'raw-markdown', 'appended-code', 'historical'] as const)('independently reconstructs the writer without executing it: %s', async scenario => {
    const f = fixture(); f.records.delete(sourceID); f.records.delete(buildID);
    const parent = f.records.get(freshID)!;
    delete parent.workflow.parentID; delete parent.workflow.documentSource; delete parent.workflow.documentExecution;
    parent.workflow.originalRequest = 'Create a Markdown file about balcony herbs';
    parent.workflow.documentFormat = requestedDocumentFormat(parent.workflow.originalRequest);
    if (scenario !== 'historical') parent.workflow.documentRawAuthoring = 'content_v1';
    parent.proposal.documentInvocation = undefined; parent.proposal.command = 'find . -maxdepth 4 -type f'; parent.operation = 'workspace_inventory'; parent.result.stdout = './MEMORY.md';
    const path = 'garden.md';
    const code = scenario === 'raw-markdown' ? '# Garden\nMint is invasive.' : scenario === 'historical' ? '# Historical agent code remains admitted\n' : rawContentCode({ version: 'raw_content_v1', content: '# Garden\nMint is invasive.' }, path) + (scenario === 'appended-code' ? '\nprint("not authorized")\n' : '');
    const invocation: DocumentInvocation = { stage: 'final', interpreter: 'python3', path, code };
    const response = await f.propose(undefined, { documentInvocation: invocation, command: documentInvocationCommand(invocation) });
    const result = await response.json();
    const accepted = ['valid', 'historical'].includes(scenario);
    expect(response.status, JSON.stringify(result)).toBe(accepted ? 200 : 409);
    if (accepted) expect(f.records.get(proposalID)?.proposal.documentInvocation).toEqual(invocation);
    else { expect(result).toMatchObject({ error: 'document_authoring_required' }); expect(f.records.has(proposalID)).toBe(false); }
    expect(f.network).not.toHaveBeenCalled();
  });
});
describe('fresh document write failure budget', () => {
  it.each(['first', 'second', 'preparation'] as const)('keeps a task-scoped confirmed failure count: %s', async scenario => {
    const f = fixture(), parent = f.records.get(freshID)!;
    parent.workflow.documentDirectoryPolicy = 'output_parent_v1';
    parent.workflow.documentWriteFailures = scenario === 'second' ? 1 : 0;
    parent.result.exitCode = 73; parent.result.status = 'failed';
    parent.result.stdout = scenario === 'preparation' ? 'KNOT_DOCUMENT_PREPARATION_FAILURE_V1 {"phase":"output_parent","noReplay":true}' : '';
    const response = await f.receipt(freshID);
    expect(response.status).toBe(200);
    expect((await response.json()).workflow.documentWriteFailures).toBe(scenario === 'first' ? 1 : 2);
    // Merely reading a receipt never increments stored state a second time.
    const reread = await f.receipt(freshID);
    expect((await reread.json()).workflow.documentWriteFailures).toBe(scenario === 'first' ? 1 : 2);
    expect(f.network).not.toHaveBeenCalled();
  });
  it('rejects renamed source after the owned task has exhausted its write corrections', async () => {
    const f = fixture(), parent = f.records.get(freshID)!;
    parent.workflow.documentDirectoryPolicy = 'output_parent_v1'; parent.workflow.documentWriteFailures = 2;
    parent.proposal.documentInvocation = undefined; parent.proposal.command = 'cat -- reference.md'; parent.operation = 'work'; parent.result.stdout = 'Read-only reference';
    const invocation: DocumentInvocation = { stage: 'source', interpreter: 'python3', path: 'another-name.html', code: '# distinct but never dispatched' };
    const response = await f.propose(undefined, { documentInvocation: invocation, command: documentInvocationCommand(invocation, undefined, false, undefined, false, true) });
    expect(response.status).toBe(409); expect(await response.json()).toMatchObject({ error: 'document_write_failures_no_replay' });
    expect(f.records.has(proposalID)).toBe(false); expect(f.network).not.toHaveBeenCalled();
  });
});
describe('fresh authoritative artifact admission', () => {
  it.each([
    ['Build a family-tree explorer with a document search panel', false, undefined],
    ['Create an animated HTML birthday card', false, 'html'],
    ['Create a document in xyz format', false, 'xyz'],
    ['Create a report as an EPUB file', false, 'epub'],
    ['Create a PDF guide about game design', true, undefined],
    ['Create a multi-kilobyte MD file', true, undefined],
    ['Create a plain PDF from complete Markdown source', true, undefined],
    ['Create a PDF, not a plain PDF', true, undefined],
  ] as const)('reconstructs the fresh route, ignoring caller measurements: %s', async (originalRequest, documentTask, artifactFormat) => {
    const f = fixture(); f.records.clear();
    const response = await f.actor.fetch(new Request('https://internal/propose', { method: 'POST', body: JSON.stringify({
      workspace, proposal: { id: proposalID, bot: 'main', conversationID, tool: 'session_input', command: 'printf synthetic-only', title: 'Fresh request', timeoutMs: 120000, expiresAt: Date.now() + 600000 },
      workflow: { rootID, originalRequest, sourceMessageID: id(9), mode: 'Answer', documentTask: false, artifactFormat: 'pdf', memoryRead: true, indexRead: true, skills: [], commands: 9999, memoryWritten: true, documentDesignJournal: 'caller-value', styleEvidencePolicy: 'caller-value' },
    }) }));
    expect(response.status).toBe(200);
    const prepared = await response.json() as KnotShellProposal;
    expect(prepared.tool).toBe('session_input'); expect(prepared.command).not.toBe('printf synthetic-only');
    const owned = f.records.get(proposalID)!.workflow;
    expect(owned).toMatchObject({ mode: 'Create', documentTask, memoryRead: false, indexRead: false, commands: 0, memoryWritten: false, documentDesignJournal: 'author_css_v1', styleEvidencePolicy: 'record_v1', documentDirectoryPolicy: 'output_parent_v1', documentRawAuthoring: 'content_v1', documentSourceAuthoring: 'text_v1' });
    if (originalRequest === 'Create a plain PDF from complete Markdown source') expect(owned.documentContentRenderer).toBeUndefined();
    if (originalRequest === 'Create a PDF, not a plain PDF') expect(owned.documentContentRenderer).toBe('content_v1');
    expect(owned.artifactFormat).toBe(artifactFormat);
    expect(owned.documentTemplate).toBeUndefined();
    expect(owned.documentFormat?.status).toBe(documentTask ? 'bound' : undefined);
    expect(f.network).not.toHaveBeenCalled();
  });
});
describe('document completion memory cannot bypass measured writer through skill drafts', () => {
  it('rejects an author-supplied note without changing any saved draft or memory', async () => {
    const f = fixture(), parent = f.records.get(freshID)!;
    parent.workflow.skillCreationCommand = 'cat /opt/knot-skills/skill-creation/SKILL.md';
    parent.workflow.skills.push(parent.workflow.skillCreationCommand);
    f.captured.push({ id: 'f'.repeat(64), proposalID: freshID, name: 'recipes.pdf', format: 'pdf', verification: { version: 'knot_document_proof_v1' } });
    const draft = { name: 'truthful-document-result', trigger: 'verified_procedure' as const, content: '---\nname: truthful-document-result\ndescription: Retain actual verdicts\n---\nRecord only established checks.', memoryNote: '2026-11-13: Independent content comparison passed.' };
    const response = await f.propose(undefined, { tool: 'skill_draft', command: skillDraftCommand(draft, proposalID), documentInvocation: undefined, skillDraft: draft });
    expect(response.status).toBe(409);
    expect(await response.json()).toMatchObject({ error: 'document_memory_protocol_required' });
    expect(f.records.has(proposalID)).toBe(false);
    expect(parent.nextProposalID).toBeUndefined();
    expect(f.network).not.toHaveBeenCalled();
  });
});
describe('general artifact closing requires actual same-chain capture', () => {
  it.each(['missing', 'same-chain', 'foreign-chain', 'wrong-format'] as const)('defers memory without matching capture: %s', async scenario => {
    const f = fixture(), parent = f.records.get(freshID)!;
    f.records.clear(); f.records.set(freshID, parent);
    parent.proposal = { ...parent.proposal, documentInvocation: undefined, tool: 'session_input', command: 'printf authored-game' };
    parent.result.stdout = 'Game file written';
    parent.workflow = { rootID, originalRequest: 'Build a playable battle game as a self-contained HTML file', sourceMessageID: id(9), mode: 'Create', documentTask: false, artifactFormat: 'html', memoryRead: true, indexRead: true, workspaceInspected: true, skills: ['cat /opt/knot-skills/web-development/SKILL.md'], commands: 1, memoryWritten: false };
    if (scenario !== 'missing') f.captured.push({ id: 'f'.repeat(64), proposalID: scenario === 'foreign-chain' ? id(999) : freshID, name: 'Battle game', format: scenario === 'wrong-format' ? 'xyz' : 'html' });
    const command = "cat >> MEMORY.md <<'KNOT_MEMORY'\n2026-11-13: Recorded actual owned capture only.\nKNOT_MEMORY";
    const response = await f.actor.fetch(new Request('https://internal/propose', { method: 'POST', body: JSON.stringify({ workspace, proposal: { id: proposalID, bot: 'main', conversationID, tool: 'session_input', title: 'Record actual result', command, timeoutMs: 120000, expiresAt: Date.now() + 600000 }, workflow: { ...parent.workflow, parentID: freshID } }) }));
    if (scenario === 'same-chain') { expect(response.status).toBe(200); expect(f.records.get(proposalID)!.operation).toBe('memory_write'); }
    else { expect(response.status).toBe(409); expect(await response.json()).toMatchObject({ error: 'memory_write_deferred', executed: false, deferred: true }); expect(f.records.has(proposalID)).toBe(false); }
    expect(f.network).not.toHaveBeenCalled();
  });
  it('forbids new work after a same-chain general capture, even without document proof', async () => {
    const f = fixture(), parent = f.records.get(freshID)!;
    f.records.clear(); f.records.set(freshID, parent);
    parent.proposal = { ...parent.proposal, documentInvocation: undefined, tool: 'session_input', command: 'printf authored-game' };
    parent.result.stdout = 'Game file written';
    parent.workflow = { rootID, originalRequest: 'Build a playable battle game as a self-contained HTML file', mode: 'Create', documentTask: false, artifactFormat: 'html', memoryRead: true, indexRead: true, workspaceInspected: true, skills: ['cat /opt/knot-skills/web-development/SKILL.md'], commands: 1, memoryWritten: false };
    f.captured.push({ id: 'f'.repeat(64), proposalID: freshID, name: 'Battle game', format: 'html' });
    const response = await f.actor.fetch(new Request('https://internal/propose', { method: 'POST', body: JSON.stringify({ workspace, proposal: { id: proposalID, bot: 'main', conversationID, tool: 'session_input', title: 'Unnecessary rework', command: 'printf forbidden-rewrite', timeoutMs: 120000, expiresAt: Date.now() + 600000 }, workflow: { ...parent.workflow, parentID: freshID } }) }));
    expect(response.status).toBe(409); expect(await response.json()).toMatchObject({ error: 'post_delivery_memory_only' }); expect(f.records.has(proposalID)).toBe(false); expect(f.network).not.toHaveBeenCalled();
  });
});
describe('final content finding repair authority', () => {
  it('persists the first grounded final finding and returns it from cache without repeating capture I/O', async () => {
    const encode = (value: string) => new TextEncoder().encode(value);
    const digest = async (bytes: Uint8Array) => [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map(value => value.toString(16).padStart(2, '0')).join('');
    const sourceBytes = encode('<html><body>Lentil bowl. Measured lentils, spinach and complete technique.</body></html>');
    const pdf = encode('%PDF-1.7\nSynthetic integrity bytes; not a rendered document.\n%%EOF');
    const png = new Uint8Array(33); png.set([137, 80, 78, 71, 13, 10, 26, 10]); png.set(encode('IHDR'), 12);
    new DataView(png.buffer).setUint32(16, 640); new DataView(png.buffer).setUint32(20, 800);
    const sourceDigest = await digest(sourceBytes);
    const f = fixture(true, { path: 'recipes.html', sha256: sourceDigest, size: sourceBytes.length, format: 'html' }, { sha256: await digest(pdf), size: pdf.length });
    f.addProof(); f.records.delete(freshID);
    const source = f.records.get(sourceID)!, proof = f.records.get(proofID)!;
    const document: StructuredDocument = { title: 'Practical meals', subtitle: '', sections: [{ id: 'meal-one', title: 'Lentil bowl', blocks: [{ kind: 'paragraph', text: 'Measured lentils, spinach and complete technique.' }] }] };
    source.proposal.documentInvocation!.code = structuredSourceCode({ version: 'content_v1', document, layout: {}, patched: false }, 'recipes.html');
    source.proposal.command = documentInvocationCommand(source.proposal.documentInvocation!);
    const inventory = structuredClone(source), inventoryID = id(20);
    inventory.proposal = { ...inventory.proposal, id: inventoryID, documentInvocation: undefined, command: 'synthetic inventory' };
    inventory.result = { ...inventory.result, proposalID: inventoryID, stdout: './recipes.html' }; inventory.operation = 'workspace_inventory';
    delete inventory.documentSourceCheck; f.records.set(inventoryID, inventory); source.workflow.parentID = inventoryID;
    const manifest = f.proofManifest();
    manifest.proofs[0].sha256 = await digest(png);
    Object.assign(manifest.verification, { textSHA256: sourceDigest, textSize: sourceBytes.length });
    proof.result.stdout = 'KNOT_DOCUMENT_V1 ' + JSON.stringify(manifest);
    const files = new Map([[f.manifest.path, pdf], ['recipes.html', sourceBytes], [manifest.proofs[0].path, png], [manifest.verification.textPath, sourceBytes]]);
    const item = { item: 'Recipes', status: 'underdeveloped_requested_item', evidenceID: 'request', quote: 'fat-loss recipes', coverageQuote: 'Measured lentils', section: 'Lentil bowl', repair: 'Explain the protein rationale for the measured recipe.' };
    const network = vi.fn(async (url: string, init?: RequestInit) => {
      const parsed = new URL(String(url));
      if (parsed.origin === 'https://checker-dead.invalid') {
        expect(JSON.parse(String(init?.body)).response_format.json_schema.name).toBe('document_completeness');
        return Response.json({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({ status: 'issues', findings: [], advisories: [], requestedItems: [item] }) } }] });
      }
      expect(parsed.pathname).toBe('/files'); expect(parsed.searchParams.get('user_id')).toBe(workspace);
      const path = parsed.searchParams.get('path')!; expect(files.has(path)).toBe(true);
      return new Response(files.get(path));
    }); vi.stubGlobal('fetch', network);
    const send = () => f.actor.fetch(new Request('https://internal/documents/capture', { method: 'POST', body: JSON.stringify({ bot: 'main', conversationID, proposalID: proofID, consentVersion: 'knot_ai_consent_v4', visualReviewAllowed: true, expiresAt: Date.now() + 40000 }) }));
    const first = await (await send()).json();
    const orders = [{ item: 'Recipes', section: 'Lentil bowl', action: 'expand', requirements: item.repair, preserve: [] }];
    expect(first).toMatchObject({ issue: 'document_content_incomplete', contentWorkOrders: orders, contentRequestedItems: [item] });
    expect(first).not.toHaveProperty('document'); expect(f.captured).toEqual([]);
    expect(f.records.get(proofID)!.documentContentFinding).toMatchObject({ issue: 'document_content_incomplete', sectionIDs: ['meal-one'], workOrders: orders, requestedItems: [item] });
    expect(f.events).toContainEqual(expect.objectContaining({ kind: 'document_content_blocked', delivered: false, workOrders: orders }));
    const calls = network.mock.calls.length;
    expect(await (await send()).json()).toMatchObject({ issue: 'document_content_incomplete', contentWorkOrders: orders, contentRequestedItems: [item] });
    expect(network).toHaveBeenCalledTimes(calls);
    expect((await (await f.receipt(proofID)).json() as ShellEvidence).workflow?.documentContentFinding).toMatchObject({ workOrders: orders, requestedItems: [item] });
    expect(source.documentSourceCheck).toMatchObject({ verdict: 'pass' });
  });
  it.each(['mapped', 'unmapped', 'ambiguous', 'already-patched'] as const)('recomputes targets from owned structured source, never supplied IDs: %s', async scenario => {
    const f = fixture(true); f.addProof(); f.records.delete(freshID);
    const document: StructuredDocument = { title: 'Practical meals', subtitle: '', sections: [{ id: 'meal-one', title: 'Lentil bowl', blocks: [{ kind: 'paragraph', text: 'Measured lentils, spinach and complete technique.' }] }, { id: 'meal-two', title: scenario === 'ambiguous' ? 'Lentil bowl' : 'Serving notes', blocks: [{ kind: 'paragraph', text: 'Preserve these serving notes.' }] }] };
    const source = f.records.get(sourceID)!, proof = f.records.get(proofID)!;
    const invocation = { ...source.proposal.documentInvocation!, code: structuredSourceCode({ version: 'content_v1', document, layout: {}, patched: scenario === 'already-patched' }, 'recipes.html') };
    source.proposal.documentInvocation = invocation; source.proposal.command = documentInvocationCommand(invocation);
    source.workflow.documentRepairPolicy = proof.workflow.documentRepairPolicy = 'single_patch_v1';
    const orders = [{ item: 'Recipes', section: scenario === 'unmapped' ? 'Absent section' : 'Lentil bowl', action: 'expand', requirements: 'Explain the protein rationale for the measured recipe.', preserve: ['Serving notes'] }];
    const items = [{ item: 'Recipes', status: 'underdeveloped_requested_item', evidenceID: 'request', quote: 'fat-loss recipes', coverageQuote: 'Measured lentils', section: orders[0].section, repair: orders[0].requirements }];
    proof.documentContentFinding = { proposalID: proofID, issue: 'document_content_incomplete', observations: ['Recipes need a developed rationale.'], sectionIDs: ['FORGED_CALLER_TARGET'], workOrders: orders, requestedItems: items };
    const receipt = await (await f.receipt(proofID)).json() as ShellEvidence;
    expect(receipt.workflow?.documentContentFinding).toMatchObject({ workOrders: orders, requestedItems: items, sectionIDs: scenario === 'mapped' ? ['meal-one'] : [] });
    expect(receipt.workflow?.documentRepairClosed).toBe(scenario === 'mapped' ? undefined : true);
    const before = JSON.stringify(proof.documentContentFinding);
    const cached = await f.actor.fetch(new Request('https://internal/documents/capture', { method: 'POST', body: JSON.stringify({ bot: 'main', conversationID, proposalID: proofID, consentVersion: 'knot_ai_consent_v4', visualReviewAllowed: true, expiresAt: Date.now() + 40000 }) }));
    expect(await cached.json()).toEqual({ issue: 'document_content_incomplete', contentObservations: ['Recipes need a developed rationale.'], contentWorkOrders: orders, contentRequestedItems: items });
    expect(JSON.stringify(f.records.get(proofID)!.documentContentFinding)).toBe(before);
    expect(f.network).not.toHaveBeenCalled(); expect(f.captured).toEqual([]);
  });
});
describe('same-task recorded build continuation', () => {
  it.each(['new-build', 'original-continuation'] as const)('actual actor dead checker records vitals and allows %s without approval', async scenario => {
    const bytes = new TextEncoder().encode('<html><body>Fresh recipes. Serves two. Simmer 100 g beans for 20 minutes.</body></html>');
    const sha256 = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))].map(b => b.toString(16).padStart(2, '0')).join('');
    const f = fixture(true, { path: 'recipes.html', sha256, size: bytes.length, format: 'html' });
    const source = f.records.get(sourceID)!, fresh = f.records.get(freshID)!;
    // A complete same-task inventory is prerequisite evidence, not a quality pass.
    const inventoryID = id(20), inventory = structuredClone(source);
    inventory.proposal = { ...inventory.proposal, id: inventoryID, documentInvocation: undefined, command: 'synthetic inventory' };
    inventory.result = { ...inventory.result, proposalID: inventoryID, stdout: './recipes.html' }; inventory.operation = 'workspace_inventory';
    delete inventory.documentSourceCheck; f.records.set(inventoryID, inventory); source.workflow.parentID = inventoryID;
    const fetcher = vi.fn(async (url: string) => {
      const parsed = new URL(String(url));
      if (parsed.origin === 'https://checker-dead.invalid') throw new Error('synthetic dead checker endpoint');
      expect(parsed.pathname).toBe('/files'); expect(parsed.searchParams.get('user_id')).toBe(workspace);
      return new Response(bytes);
    }); vi.stubGlobal('fetch', fetcher);
    const checkedIDs = scenario === 'new-build' ? [sourceID] : [sourceID, freshID];
    if (scenario === 'new-build') { f.records.delete(buildID); f.records.delete(freshID); }
    for (const recordID of checkedIDs) {
      delete f.records.get(recordID)!.documentSourceCheck;
      const response = await f.actor.fetch(new Request('https://internal/documents/source-check', { method: 'POST', body: JSON.stringify({ bot: 'main', conversationID, proposalID: recordID, consentVersion: 'knot_ai_consent_v4', expiresAt: Date.now() + 40000 }) }));
      const result = await response.json() as { check: Record<string, unknown>; workflow: ShellWorkflow };
      expect(result.check).toMatchObject({ verdict: 'unconfirmed', observations: [], contentCheckAttempts: [{ reason: 'content_check_transport_error' }, { reason: 'content_check_transport_error' }] });
      expect(result.workflow.documentContentFinding).toBeUndefined();
      expect(f.events.filter(e => e.proposalID === recordID && e.kind === 'document_content_check_attempt')).toMatchObject([{ attempt: 1, operation: 'source', model: 'openai/gpt-4o', outcome: 'unconfirmed', responseBytes: 0 }, { attempt: 2, operation: 'source', outcome: 'unconfirmed' }]);
      expect(f.events).toContainEqual(expect.objectContaining({ kind: 'document_source_unconfirmed', blocking: false, delivered: false }));
    }
    const response = scenario === 'original-continuation' ? await f.propose() : await f.actor.fetch(new Request('https://internal/propose', { method: 'POST', body: JSON.stringify({ proposal: { ...fresh.proposal, id: proposalID, tool: 'document_script', documentInvocation: f.execution.invocation, command: documentInvocationCommand(f.execution.invocation, f.execution.source, true, f.execution.resident) }, workspace, workflow: { ...source.workflow, parentID: sourceID } }) }));
    expect(response.status).toBe(200);
    const prepared = await response.json() as KnotShellProposal;
    expect(prepared.tool).toBe(scenario === 'new-build' ? 'document_script' : 'session_input');
    if (scenario === 'original-continuation') {
      expect(prepared.command).toBe(documentProofCommand(f.manifest, buildID, true, true, true));
      expect(f.events).toContainEqual(expect.objectContaining({ kind: 'document_build_continued', buildProposalID: buildID, newBuildExecution: false }));
    }
    expect(f.events.some(e => e.kind === 'document_source_blocked' || e.kind === 'document_work_unavailable')).toBe(false);
    expect(f.network).not.toHaveBeenCalled();
  });
  it.each([false, true])('projects only the original owned chain before/after proof/capture; fresh=%s', async quality => {
    const f = fixture(quality);
    const before = await (await f.receipt(freshID)).json() as ShellEvidence;
    expect(before.documentChain).toMatchObject({ buildProposalID: buildID, outputPath: f.manifest.path, outputSHA256: f.manifest.sha256, sourceSHA256: f.execution.source.sha256, sourceSameBytes: true, newBuildRequired: false, remaining: ['independent_proof', 'content_comparison', ...(quality ? ['visual_review'] : []), 'capture'] });
    expect(before.documentChain?.proofProposalID).toBeUndefined();
    f.addProof();
    const proven = await (await f.receipt(freshID)).json() as ShellEvidence;
    expect(proven.documentChain).toMatchObject({ buildProposalID: buildID, proofProposalID: proofID, remaining: ['content_comparison', ...(quality ? ['visual_review'] : []), 'capture'] });
    f.captured.push({ id: 'f'.repeat(64), sha256: f.manifest.sha256, sourcePath: f.manifest.path, proposalID: proofID });
    const captured = await (await f.receipt(freshID)).json() as ShellEvidence;
    expect(captured.documentChain).toMatchObject({ capturedDocumentID: 'f'.repeat(64), remaining: [] });
    expect(f.network).not.toHaveBeenCalled();
  });
  it('returns the same chain with cached source-check results and requires fresh consent at capture', async () => {
    const f = fixture(true);
    const checked = await f.actor.fetch(new Request('https://internal/documents/source-check', { method: 'POST', body: JSON.stringify({ bot: 'main', conversationID, proposalID: freshID, consentVersion: 'knot_ai_consent_v4', expiresAt: Date.now() + 40000 }) }));
    expect(await checked.json()).toMatchObject({ check: { verdict: 'pass' }, documentChain: { buildProposalID: buildID, newBuildRequired: false } });
    const refused = await f.actor.fetch(new Request('https://internal/documents/capture', { method: 'POST', body: JSON.stringify({ bot: 'main', conversationID, proposalID: buildID, consentVersion: 'knot_ai_consent_v3', visualReviewAllowed: false, expiresAt: Date.now() + 40000 }) }));
    expect(refused.status).toBe(400); expect(await refused.json()).toEqual({ error: 'document_review_choice_required' });
    expect(f.network).not.toHaveBeenCalled();
  });
  it.each(['cancelled', 'uncertain', 'truncated', 'changed-source', 'content-finding'] as const)('omits continuation projection for %s ancestry', async scenario => {
    const f = fixture(true), build = f.records.get(buildID)!;
    if (scenario === 'cancelled') build.cancelled = true;
    if (scenario === 'uncertain') build.result.status = 'uncertain';
    if (scenario === 'truncated') build.result.contextTruncated = true;
    if (scenario === 'changed-source') f.records.get(freshID)!.result.stdout = 'KNOT_DOCUMENT_SOURCE_V1 ' + JSON.stringify({ ...f.freshSource, sha256: 'c'.repeat(64) });
    if (scenario === 'content-finding') build.documentContentFinding = { proposalID: buildID, issue: 'document_content_incomplete', observations: ['Synthetic gap'] };
    expect((await (await f.receipt(freshID)).json() as ShellEvidence).documentChain).toBeUndefined();
    expect(f.network).not.toHaveBeenCalled();
  });
  it('prepares the all-page proof only for a fresh workflow, preserving historical framing', async () => {
    const f = fixture(true), response = await f.propose();
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ tool: 'session_input', command: documentProofCommand(f.manifest, buildID, true, true, true) });
    expect(f.network).not.toHaveBeenCalled();
  });
  it('routes identical bytes under fresh names to the first original proof, never a second build', async () => {
    const f = fixture(), originalBuild = structuredClone(f.records.get(buildID));
    const build = f.records.get(buildID)!;
    expect(verifiedDocumentExecution({ ...build.result, reviewedCommand: build.proposal.command, documentInvocation: build.proposal.documentInvocation, workflow: build.workflow, evidence: [f.records.get(sourceID)!, build].map(r => ({ ...r.result, reviewedCommand: r.proposal.command, documentInvocation: r.proposal.documentInvocation })) } as ShellEvidence, f.manifest)).toBe(true);
    const response = await f.propose();
    expect(response.status).toBe(200);
    const proposal = await response.json() as KnotShellProposal;
    expect(proposal).toMatchObject({ id: proposalID, tool: 'session_input', command: documentProofCommand(f.manifest, buildID, true, true), receiptKind: 'internal' });
    expect(proposal.documentInvocation).toBeUndefined();
    const prepared = f.records.get(proposalID)!;
    expect(prepared.workflow).toMatchObject({ rootID, parentID: freshID, commands: 9, documentExecution: f.execution, documentProof: { manifest: f.manifest, sourceProposalID: buildID }, documentSource: { source: f.freshSource, proposalID: freshID } });
    expect(f.records.get(buildID)).toEqual(originalBuild);
    expect([...f.records.values()].filter(r => r.proposal.documentInvocation?.stage === 'build')).toHaveLength(1);
    expect(f.events).toContainEqual(expect.objectContaining({ kind: 'document_build_continued', buildProposalID: buildID, nextStep: 'independent_proof', newBuildExecution: false }));
    const repeated = await f.propose(undefined, { id: id(10) });
    expect(await repeated.json()).toEqual(proposal);
    expect(f.records.size).toBe(4);
    // Simulate the new verifier's COMPLETE receipt, without running its command.
    // The ordinary receipt/proof gate must still recognize the ORIGINAL build.
    const proofRecord = f.records.get(proposalID)!;
    proofRecord.phase = 'finished'; proofRecord.logFinal = true; proofRecord.sessionID = 'synthetic-owned-session';
    proofRecord.result = { ...build.result, proposalID, stdout: 'KNOT_DOCUMENT_V1 ' + JSON.stringify(f.proofManifest()) };
    const responseReceipt = await f.receipt(proposalID);
    expect(responseReceipt.status).toBe(200);
    const receipt = await responseReceipt.json() as ShellEvidence;
    const manifest = documentManifest(receipt)!;
    expect(verifiedDocumentProof(receipt, manifest)).toMatchObject({ sourceSHA256: f.manifest.sha256, textPath: 'deliverables/knot-proof-' + buildID + '/text.txt' });
    expect(receipt.workflow?.documentProof?.sourceProposalID).toBe(buildID);
    expect(receipt.workflow?.commands).toBe(9);
    expect(f.network).not.toHaveBeenCalled();
  });
  it('returns the exact already-proven ancestor for capture with no new command', async () => {
    const f = fixture(); f.addProof();
    const response = await f.propose();
    expect(response.status).toBe(409);
    expect(await response.json()).toMatchObject({ error: 'document_build_continuation_available', continuationReceiptID: proofID });
    expect(f.records.has(proposalID)).toBe(false);
    expect(f.network).not.toHaveBeenCalled();
  });
  it.each(['cancelled-build', 'cancelled-source', 'cancelled-parent', 'failed', 'uncertain', 'incomplete', 'truncated', 'nonancestor', 'finding', 'attempted-proof', 'proof-in-another-branch', 'no-budget', 'stop'] as const)('never adopts or re-proves unsafe evidence: %s', async scenario => {
    const f = fixture(), build = f.records.get(buildID)!, fresh = f.records.get(freshID)!;
    if (scenario === 'cancelled-build') build.cancelled = true;
    if (scenario === 'cancelled-source') f.records.get(sourceID)!.cancelled = true;
    if (scenario === 'cancelled-parent') fresh.cancelled = true;
    if (scenario === 'failed') { build.result.status = 'failed'; build.result.exitCode = 1; }
    if (scenario === 'uncertain') { build.phase = 'uncertain'; build.result.status = 'uncertain'; }
    if (scenario === 'incomplete') build.result.outputComplete = false;
    if (scenario === 'truncated') build.result.contextTruncated = true;
    if (scenario === 'nonancestor') fresh.workflow.parentID = sourceID;
    if (scenario === 'finding') build.documentContentFinding = { proposalID: buildID, issue: 'document_content_incomplete', observations: ['Synthetic finding'] };
    if (scenario === 'attempted-proof') f.addProof(false);
    if (scenario === 'proof-in-another-branch') { f.addProof(false); fresh.workflow.parentID = buildID; }
    if (scenario === 'no-budget') fresh.workflow.commands = shellCommandLimit;
    const stop = new AbortController(); if (scenario === 'stop') stop.abort();
    const response = await f.propose(stop.signal);
    expect(response.status).toBe(409);
    expect(f.records.has(proposalID)).toBe(false);
    expect([...f.records.values()].filter(r => r.proposal.documentInvocation?.stage === 'build')).toHaveLength(1);
    expect(f.events.some(event => event.kind === 'review_created')).toBe(false);
    expect(f.network).not.toHaveBeenCalled();
  });
});
