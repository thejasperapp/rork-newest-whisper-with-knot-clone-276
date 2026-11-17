// @vitest-environment node
// Real live orchestration + real slice helper state against synthetic network
// boundaries. No actual model, shell, browser, renderer or capture is run.
import { afterEach, describe, expect, it, vi } from 'vitest';
vi.mock('cloudflare:workers', () => ({ DurableObject: class {} }));
import { knotLive } from '../../functions/knot-live';
import { beginDocumentProgram, appendDocumentProgram, documentProgramReceipt, type DocumentProgram, type DocumentProgramOwner } from '../../functions/knot-document-program';
import { documentSkillReadCommand } from '../../functions/knot-document-proof';
import type { ShellWorkflow } from '../../functions/knot-shell';
import { safeKnotActivityDetail } from '../../functions/knot-activity';
import { documentAuthoringFormat } from '../../functions/knot-document-authoring';
import { knotCreationTurnMs } from '../../functions/knot-turn-economics';
import { documentSliceTokenLimit } from '../../functions/knot-document-authoring-context';

function streamed(envelope: { choices: { finish_reason: string; message: Record<string, unknown> }[] }): Response {
  return new Response('data: ' + JSON.stringify({ choices: envelope.choices.map((choice, index) => ({ index, delta: choice.message, finish_reason: choice.finish_reason })) }) + '\n\ndata: [DONE]\n\n', { headers: { 'Content-Type': 'text/event-stream' } });
}
const id = (n: number) => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');
afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });
describe('same-provider sliced authoring in the actual live orchestrator', () => {
  it.each([750, 1500, 3000, 6000])('budgets for the legal escaped JSON byte ceiling, not typical code density: %s', target => {
    // Response token budgets are independent of storage-piece ceilings.
    // C0 escapes cost six JSON bytes per code point.
    const code = target >= 3000 ? '\u0001'.repeat(2999) + '🙂' : '\u0001'.repeat(target);
    const codeBytes = Buffer.byteLength(JSON.stringify(code));
    expect(Array.from(code).length).toBeLessThanOrEqual(target);
    expect(codeBytes).toBeLessThanOrEqual(18000);
    const responseBytes = Buffer.byteLength(JSON.stringify({ code, final: false }));
    // Explicit conservative assumption: one JSON byte/token plus 25% margin.
    // This is budget headroom, not proof of provider enforcement or throughput.
    expect(documentSliceTokenLimit(target)).toBeGreaterThanOrEqual(Math.ceil(responseBytes * 1.25));
    expect(documentSliceTokenLimit(target)).toBeLessThanOrEqual(128000);
  });
  it('scales byte-derived budgets monotonically and rejects invalid targets', () => {
    expect([750, 1500, 3000, 6000, 64000].map(documentSliceTokenLimit)).toEqual([5657, 11282, 22532, 45032, 92529]);
    expect(documentSliceTokenLimit(2000)).toBeLessThanOrEqual(16384);
    for (const target of [NaN, Infinity, -1, 0, 1.5, 64001]) expect(() => documentSliceTokenLimit(target)).toThrow('document_program_invalid');
  });
  it('leaves exact storage metering to the harness, not the model grammar', () => {
    const code = documentAuthoringFormat.json_schema.schema.properties.code as Record<string, unknown>;
    expect(code).toEqual({ type: 'string', description: expect.any(String) });
    expect(code).not.toHaveProperty('pattern');
    expect(code).not.toHaveProperty('maxLength');
  });
  it('retains only allowlisted slice checks and numeric diagnostics, never provider text', () => {
    const facts = { check: 'slice_parse', sliceIndex: 1, attempt: 2, attempts: 2, finishReason: 'length', schemaHash: 'a'.repeat(64), deadlineSource: 'owned_turn', expiresAt: 1794595000000, requestedCharacters: 1500 };
    expect(safeKnotActivityDetail({ ...facts, code: 'private source', providerBody: 'private response', prompt: 'private prompt', arbitrary: 'private' })).toEqual(facts);
    expect(safeKnotActivityDetail({ check: 'private response', sliceIndex: 32, requestedCharacters: 64001, deadlineSource: 'private' })).toBeUndefined();
  });
  it('persists content-free exact-byte prompt, storage and absolute-clock metrics only', () => {
    const facts = { authoringTotalPromptBytes: 34000, authoringPromptOverageBytes: 1232, authoringBasePromptBytes: 31000, authoringReadBytes: 15000, authoringDevelopedBytes: 8000, authoringDescriptorBytes: 1500, authoringPromptTargetExceeded: true, sizeClass: 'document_program_74kb', turnElapsedMs: 180001, sliceCharacterLimit: 24000, sliceByteLimit: 24576 };
    expect(safeKnotActivityDetail({ ...facts, prompt: 'private', code: 'private', providerBody: 'private', credentials: 'private' })).toEqual(facts);
    expect(safeKnotActivityDetail({ turnElapsedMs: -1, authoringTotalPromptBytes: Infinity, sizeClass: 'invented', sliceByteLimit: 24577 })).toBeUndefined();
  });
  it.each(['sealed', 'sealed-large', 'claude', 'measure', 'truncated', 'invalid-json', 'oversize', 'stopped', 'tampered-receipt', 'tampered-history', 'provider-failure', 'multiple-choices', 'tool-envelope', 'malformed-middle', 'fenced', 'prose', 'length-then-stop', 'target-then-stop', 'empty-then-stop', 'raw-html', 'timeout-then-stop', 'timeout-exhausted', 'stopped-retry', 'ambiguous', 'refused', 'content-filtered', 'open-string', 'raw-md', 'general-html', '520-then-stop', '520-exhausted', 'selection-520', 'whole-wire-large', 'gpt-bounded', 'transport-overflow'] as const)('keeps original evidence and fails closed without execution: %s', async scenario => {
    const sonnet = scenario !== 'gpt-bounded';
    const tokenLimit = documentSliceTokenLimit(sonnet ? 8000 : 2000);
    const requestID = id(1), rootID = id(2), sourceMessageID = id(3), conversationID = id(4), parentID = id(5), workspace = 'whisper-' + 'a'.repeat(48);
    const aborter = new AbortController(), calls: Record<string, any>[] = [], activities: Record<string, any>[] = [], proposals: Record<string, any>[] = [], timeline: string[] = [], unexpected: string[] = [];
    const fullReference = 'Complete reference evidence: preserve every line.\n'.repeat(scenario === 'transport-overflow' ? 12000 : 1800);
    const ancestor = { proposalID: id(6), operation: 'skill_read', reviewedCommand: 'cat /opt/knot-skills/reference/SKILL.md', stdout: 'Different complete ancestor skill bytes 🙂\n'.repeat(900), stderr: 'Retained original warning', status: 'completed', exitCode: 0, outputComplete: true, truncated: false, contextTruncated: false, terminationConfirmed: true };
    const completeFailure = { proposalID: id(7), reviewedCommand: 'python3 failed.py', stdout: '', stderr: 'Original failed attempt must remain evidence', status: 'failed', exitCode: 1, outputComplete: true, truncated: false, terminationConfirmed: true };
    const workflow: ShellWorkflow = { rootID, sourceMessageID, originalRequest: 'Create a PDF guide from the complete reference', mode: 'Create', documentTask: true, documentPipeline: 'agent_v2', documentPolicy: 'author_v1', memoryRead: true, indexRead: true, workspaceInspected: true, skills: [documentSkillReadCommand], documentSkillCommand: documentSkillReadCommand, commands: 4, memoryWritten: false };
    if (scenario === 'raw-md') { workflow.originalRequest = 'Create a Markdown guide from the complete reference'; workflow.documentFormat = { version: 'original_format_v1', status: 'bound', format: 'md' }; }
    if (scenario === 'general-html') { workflow.originalRequest = 'Build a playable monster battle game as a self-contained HTML file'; workflow.documentTask = false; workflow.artifactFormat = 'html'; workflow.skills = ['cat /opt/knot-skills/games-web/SKILL.md']; delete workflow.documentSkillCommand; }
    let program: DocumentProgram | undefined, cancelled = false, slices = 0;
    const env = { SUPABASE_SERVICE_ROLE_KEY: 'synthetic-signing-only', SIDECAR_TOKEN_WHISPER: 'synthetic-sidecar-only', EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY: 'synthetic-gateway-only', EXPO_PUBLIC_TOOLKIT_URL: 'https://synthetic.invalid', DO: { fetch: vi.fn(async (request: Request) => {
      const path = new URL(request.url).pathname; timeline.push(path);
      if (path === '/admit') return Response.json({ ok: true });
      const body = await request.json() as Record<string, any>;
      if (path === '/receipt') return Response.json({ proposalID: parentID, bot: 'main', conversationID, status: 'completed', exitCode: 0, sessionID: 'synthetic-owned-session', outputComplete: true, terminationConfirmed: true, truncated: false, stdout: fullReference, stderr: '', reviewedCommand: 'cat -- full-reference.md', workflow, evidence: [ancestor, completeFailure] });
      if (path === '/discovery') return Response.json({ ok: true, service: 'knot-sidecar', tools: [
        { name: 'session_input', method: 'POST', path: '/sessions/:id/input', request: { data: 'Exact command' } },
        { name: 'session_open', method: 'POST', path: '/sessions' }, { name: 'session_status', method: 'GET', path: '/sessions/:id' },
        { name: 'session_read', method: 'GET', path: '/sessions/:id/log?offset=N' }, { name: 'session_close', method: 'DELETE', path: '/sessions/:id' }, { name: 'capabilities', method: 'GET', path: '/capabilities' },
      ] });
      if (path === '/workspace/resolve') return Response.json({ workspace });
      if (path === '/activity') { activities.push(body); return Response.json({ ok: true }); }
      if (path === '/document-program/begin') {
        // Foreground workspace turn, with NO browser capability/version: the
        // preparation still receives a real future owned-turn deadline.
        expect(body.expiresAt - Date.now()).toBeGreaterThan(knotCreationTurnMs - 10000);
        expect(body.expiresAt - Date.now()).toBeLessThanOrEqual(knotCreationTurnMs);
        expect(body.owner).toEqual({ workspace, bot: 'main', conversationID, rootID, parentID, sourceMessageID });
        program = await beginDocumentProgram(body.owner as DocumentProgramOwner, body.preparation, body.expiresAt, Date.now()); return Response.json(documentProgramReceipt(program));
      }
      if (path === '/document-program/append') {
        expect(proposals).toHaveLength(0); expect(program).toBeDefined();
        program = await appendDocumentProgram(program!, body.owner, body.slice, Date.now());
        const receipt = documentProgramReceipt(program);
        if (scenario === 'tampered-receipt') receipt.prefixSHA256 = 'f'.repeat(64);
        if (scenario === 'tampered-history' && receipt.count === 2) receipt.slices[0].sha256 = 'f'.repeat(64);
        return Response.json(receipt);
      }
      if (path === '/document-program/cancel') { cancelled = true; return Response.json({ cancelled: true }); }
      if (path === '/propose') {
        if (scenario !== 'measure') { expect(program?.state).toBe('sealed'); expect(body.proposal.documentProgramID).toBe(program?.id); }
        proposals.push(body); return Response.json({ ...body.proposal, taskID: rootID, sourceMessageID, operation: 'work' });
      }
      // End the synthetic observation at the genuine handoff boundary. Do not
      // manufacture a successful command receipt, artifact, or tool-card run.
      if (path === '/foreground-ready') { aborter.abort(); throw new DOMException('Synthetic stop after handoff', 'AbortError'); }
      unexpected.push(path); throw new Error('Unexpected route');
    }) } };
    const prefix = '# Synthetic immutable prefix 🙂\n' + '#'.repeat(['length-then-stop', 'target-then-stop', 'timeout-then-stop'].includes(scenario) ? 1400 : 2900), suffix = '\n# exact final suffix\n';
    const fragments = scenario === 'gpt-bounded' ? ['#'.repeat(1900), suffix] : scenario === 'whole-wire-large' ? ['#'.repeat(63999)] : scenario === 'oversize' ? ['#'.repeat(6001)] : scenario === 'target-then-stop' ? ['#'.repeat(3001), suffix] : scenario === 'open-string' || scenario === 'raw-md' ? ['from pathlib import Path\nPath("synthetic.' + (scenario === 'raw-md' ? 'md' : 'html') + '").write_text("""First developed section\n', 'Second developed section\n""", encoding="utf-8")\n'] : scenario === 'sealed-large' ? Array.from({ length: 6 }, () => '\n' + '#'.repeat(2500)) : [prefix, suffix];
    vi.stubGlobal('fetch', vi.fn(async (url: string, init: RequestInit) => {
      expect(String(url)).toBe('https://synthetic.invalid/v2/vercel/v1/chat/completions');
      const body = JSON.parse(String(init.body)); calls.push(body);
      const hasFullReference = body.messages.some((m: any) => typeof m.content === 'string' && (m.content.includes(fullReference) || m.content.includes(JSON.stringify(fullReference).slice(1, -1))));
      expect(hasFullReference).toBe(body.response_format?.json_schema?.name !== 'knot_document_decision');
      expect(body.model).toBe(sonnet ? 'anthropic/claude-sonnet-4.6' : 'openai/gpt-4o');
      const schemaName = body.response_format?.json_schema?.name;
      if (schemaName === 'knot_document_decision') {
        expect(body.stream).toBe(false);
        timeline.push('descriptor-selection'); expect(body.max_tokens).toBe(1500);
        if (scenario === 'selection-520' && calls.length === 1) return Response.json({ error: 'synthetic' }, { status: 520 });
        expect(JSON.stringify(body.response_format)).toContain('document_prepare');
        expect(JSON.stringify(body.response_format)).not.toContain('"code"');
        return Response.json({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({ selection: { tool: 'document_prepare', arguments: { stage: ['raw-md', 'general-html'].includes(scenario) ? 'final' : 'source', interpreter: 'python3', path: scenario === 'raw-md' ? 'synthetic.md' : 'synthetic.html', title: '', deliveryLabel: '', authoring: scenario === 'measure' ? 'measure' : 'author' } } }) } }] });
      }
      expect(body.stream).toBe(true);
      expect(schemaName).toBe('knot_document_slice'); expect(proposals).toHaveLength(0);
      expect(body.response_format.json_schema.schema.properties.code).toEqual({ type: 'string', description: expect.any(String), maxLength: sonnet ? 8000 : 2000 });
      expect(body.messages[0].content).toMatch(/^DOCUMENT PROGRAM AUTHORING ONLY\./);
      expect(body.messages.filter((m: any) => m.tool_calls)).toEqual([]);
      // Author-only context deliberately excludes unrelated chat/health history.
      expect(JSON.stringify(body.messages)).not.toContain('Synthetic supplied health context');
      expect(JSON.stringify(body.messages)).not.toContain('Synthetic original conversation');
      const ledger = JSON.parse(body.messages.find((m: any) => typeof m.content === 'string' && m.content.startsWith('COMPLETE LIVE GUIDANCE')).content.split('\n').slice(1).join('\n'));
      expect(ledger.reads).toEqual(expect.arrayContaining([expect.objectContaining({ payload: 1, outputComplete: true, truncated: false, terminationConfirmed: true }), expect.objectContaining({ payload: 0, proposalIDs: [ancestor.proposalID] })]));
      for (const text of [fullReference, ancestor.stdout, ancestor.stderr]) expect(body.messages.some((m: any) => typeof m.content === 'string' && m.content.endsWith('\n' + text))).toBe(true);
      expect(ledger.work).toContainEqual(expect.objectContaining({ proposalID: completeFailure.proposalID, stderr: completeFailure.stderr, status: 'failed' }));
      const descriptor = JSON.parse(body.messages.find((m: any) => typeof m.content === 'string' && m.content.startsWith('CURRENT OWNED AUTHORING DESCRIPTOR')).content.split('\n').slice(1).join('\n'));
      const { originalRequest: _originalRequest, ...expectedOwned } = workflow;
      expect(descriptor).toEqual({ ...expectedOwned, parentID, originalRequest: workflow.originalRequest });
      expect(Buffer.byteLength(JSON.stringify(calls[0].messages))).toBeLessThan(Buffer.byteLength(JSON.stringify(body.messages)));
      expect(JSON.stringify(calls[0].messages)).not.toContain(ancestor.stdout.slice(0, 100));
      expect(JSON.stringify(calls[0].messages)).toContain(rootID);
      slices++; timeline.push('slice-' + slices);
      const last = body.messages.at(-1).content as string;
      expect(last).toContain('storage partitioning is done exactly by the harness');
      expect(last).toContain('set final=false');
      expect(last).not.toMatch(/Output at most|hard slice ceiling|smaller stated target/);
      expect(body.messages.some((m: any) => m.role === 'system' && /^(?:DOCUMENT AUTHORSHIP AND TRANSPORT|ORIGINAL-FORMAT DOCUMENT DELIVERY):/.test(m.content))).toBe(false);
      expect(body.messages.some((m: any) => m.role === 'system' && m.content.includes('whole SEALED program, not this individual response'))).toBe(true);
      if (scenario === 'raw-md') expect(body.messages.some((m: any) => m.role === 'system' && m.content.includes('Raw final bytes retain exactly the bound extension'))).toBe(true);
      if (scenario === 'general-html') {
        const policies = body.messages.filter((m: any) => m.role === 'system').map((m: any) => m.content).join('\n');
        expect(policies).toContain('GENERAL HTML ARTIFACT');
        expect(policies).not.toContain('PER-DOCUMENT DESIGN:');
        expect(policies).not.toContain('For PDF/Office, author');
        expect(policies).not.toContain('CURRENT QUALITY POLICY');
      }
      expect(body.max_tokens).toBe(tokenLimit);
      expect(body.response_format.json_schema.schema.properties.code).not.toHaveProperty('pattern');
      const accepted = program?.slices.length ?? 0;
      expect(last).toContain('IMMUTABLE EXACT PREFIX'); expect(last.endsWith(JSON.stringify(fragments.slice(0, accepted).join('')))).toBe(true);
      // Every assistant tool-call envelope has its matching result before the
      // slice call; no dangling preparation call is sent upstream.
      for (const [index, message] of body.messages.entries()) for (const call of message.tool_calls ?? []) expect(body.messages.slice(index + 1).some((m: any) => m.role === 'tool' && m.tool_call_id === call.id)).toBe(true);
      if (scenario === 'stopped' || scenario === 'stopped-retry' && slices === 2) { aborter.abort(); throw new DOMException('Synthetic Stop', 'AbortError'); }
      if (scenario === 'provider-failure') throw new Error('Synthetic provider failure');
      if (scenario === '520-exhausted' || scenario === '520-then-stop' && slices === 1) return Response.json({ error: 'synthetic' }, { status: 520 });
      if (scenario === 'timeout-exhausted' || scenario === 'timeout-then-stop' && slices === 1) throw new DOMException('Synthetic slice deadline', 'TimeoutError');
      if (scenario === 'content-filtered') return streamed({ choices: [{ finish_reason: 'content_filter', message: { content: '' } }] });
      if (scenario === 'refused') return streamed({ choices: [{ finish_reason: 'stop', message: { refusal: 'Synthetic refusal', content: '' } }] });
      const corrupt = scenario === 'invalid-json' || scenario === 'stopped-retry' && slices === 1 || scenario === 'malformed-middle' && slices === 2;
      let content = corrupt ? '{"code":' : JSON.stringify({ code: scenario === 'oversize' ? '#'.repeat(6001) : scenario === 'target-then-stop' && slices === 1 ? '#'.repeat(3001) : scenario === 'raw-html' ? '<!doctype html><html><body>Not Python</body></html>' : fragments[accepted], final: accepted === fragments.length - 1 });
      if (scenario === 'fenced') content = '```json\n' + content + '\n```';
      if (scenario === 'prose') content = 'Here is the slice:\n' + content + '\nEnd of slice.';
      if (scenario === 'ambiguous') content += '\n' + content;
      if (scenario === 'empty-then-stop' && slices === 1) content = '';
      const choice = { finish_reason: scenario === 'truncated' || scenario === 'length-then-stop' && slices === 1 ? 'length' : 'stop', message: { ...(scenario === 'tool-envelope' ? { tool_calls: [] } : {}), content } };
      return streamed({ choices: scenario === 'multiple-choices' ? [choice, choice] : [choice] });
    }));
    let pending: Promise<unknown> | undefined;
    const response = await knotLive(new Request('https://synthetic.invalid/knot/live', { method: 'POST', signal: aborter.signal, body: JSON.stringify({ requestID, consentVersion: 'knot_ai_consent_v4', ...(sonnet ? { taskModelConsentVersion: 'knot_task_models_v1' } : {}), documentProgramVersion: 'knot_document_program_v3', foregroundTurnVersion: 'knot_foreground_turn_v1', message: workflow.originalRequest, bot: 'main', healthContext: 'Synthetic supplied health context', history: [{ role: 'user', content: 'Synthetic original conversation' }], isWebQuery: false, sharedConversation: false, conversationID, sourceMessageID, shellResultID: parentID }) }), env, rootID, { waitUntil: work => { pending = work; } });
    expect(response.status).toBe(200); const wire = await response.text(); await pending;
    const events = wire.split('\n\n').filter(frame => frame.startsWith('data: ')).map(frame => JSON.parse(frame.slice(6)));
    expect(unexpected).toEqual([]);
    // Additive live observations retain legacy wire types while carrying the
    // exact kind/linkage/sanitized facts persisted for the Events rollup.
    for (const event of events.filter(event => event.activity)) {
      const persisted = activities.find(activity => activity.sequence === event.sequence);
      expect(persisted).toBeDefined();
      expect(event.activity).toMatchObject({ id: `${requestID}:${event.sequence}`, requestID, sequence: event.sequence, kind: persisted.kind, taskID: persisted.taskID });
      expect(event.activity.sourceMessageID).toBe(persisted.sourceMessageID);
      expect(event.activity.detail).toEqual(persisted.detail);
    }
    const authorFrames = events.filter(event => event.activity?.kind.startsWith('document_program_'));
    if (scenario !== 'measure') expect(authorFrames.length).toBeGreaterThan(0);
    expect(authorFrames.every(event => event.type === 'accepted')).toBe(true);
    expect(JSON.stringify(events.map(event => event.activity))).not.toMatch(/Synthetic immutable|Complete reference|synthetic-gateway-only/);
    const attempts = activities.filter(a => a.kind === 'document_program_attempt');
    const authoringCalls = calls.filter(c => c.response_format?.json_schema?.name === 'knot_document_slice');
    if (scenario === 'transport-overflow') {
      expect(attempts.length).toBeGreaterThan(0);
      expect(authoringCalls).toHaveLength(0);
      expect(timeline).not.toContain('/document-program/append');
      expect(events.find(e => e.type === 'document_work_unavailable')).toMatchObject({ reason: 'document_program_capacity_exceeded', check: 'program_size', branch: 'program_size', authoringTotalPromptBytes: expect.any(Number), commandDispatched: false });
      expect(events.find(e => e.type === 'document_work_unavailable').authoringTotalPromptBytes).toBeGreaterThan(524288);
    } else {
      expect(attempts).toHaveLength(authoringCalls.length - activities.filter(a => a.kind === 'model_transport_retry' && a.detail.stage === 'document_authoring').length);
    }
    for (const call of authoringCalls) {
      const expectedHash = Buffer.from(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(call.response_format.json_schema.schema)))).toString('hex');
      expect(attempts.every(a => a.detail.schemaHash === expectedHash)).toBe(true);
      const promptBytes = Buffer.byteLength(JSON.stringify(call.messages));
      const totalBytes = promptBytes + Buffer.byteLength(JSON.stringify(call.response_format));
      expect(activities.some(a => a.detail?.stage === 'document_authoring' && a.detail.promptBytes === promptBytes && a.detail.authoringTotalPromptBytes === totalBytes && a.detail.authoringPromptOverageBytes === Math.max(0, totalBytes - 32768) && a.detail.authoringPromptTargetExceeded === (totalBytes > 32768))).toBe(true);
    }
    expect(events.filter(event => event.activity).every(event => Number.isSafeInteger(event.activity.detail?.turnElapsedMs) && event.activity.detail.turnElapsedMs >= 0)).toBe(true);
    expect(activities.some(a => a.detail?.sizeClass === 'document_program_74kb' && a.detail.programByteCeiling === 74000)).toBe(true);
    expect(events.some(e => e.type === 'text')).toBe(false);
    expect(JSON.stringify(activities)).not.toMatch(/Synthetic immutable|Complete reference|synthetic-gateway-only/);
    if (['sealed', 'sealed-large', 'claude', 'measure', 'malformed-middle', 'fenced', 'prose', 'length-then-stop', 'target-then-stop', 'empty-then-stop', 'timeout-then-stop', 'open-string', 'raw-md', 'general-html', 'oversize', '520-then-stop', 'selection-520', 'whole-wire-large', 'gpt-bounded'].includes(scenario)) {
      expect(proposals).toHaveLength(1);
      if (scenario === 'general-html') {
        expect(proposals[0].workflow).toMatchObject({ documentTask: false, artifactFormat: 'html' });
        expect(proposals[0].workflow.documentFormat).toBeUndefined();
        expect(proposals[0].proposal.documentInvocation).toMatchObject({ stage: 'final', interpreter: 'python3', path: 'synthetic.html' });
        expect(proposals[0].proposal.command).toContain('KNOT_RAW_DOCUMENT_INVOKE');
      }
      expect(proposals[0].proposal.documentInvocation.code).toBe(scenario === 'measure' ? '' : fragments.join(''));
      const repaired = ['malformed-middle', 'length-then-stop', 'empty-then-stop'].includes(scenario);
      const transportRepaired = ['timeout-then-stop', '520-then-stop', 'selection-520'].includes(scenario);
      expect(calls.map(c => c.max_tokens)).toEqual(scenario === 'measure' ? [1500] : [...(scenario === 'selection-520' ? [1500, 1500] : [1500]), ...Array.from({ length: fragments.length + Number(repaired || transportRepaired && scenario !== 'selection-520') }, () => tokenLimit)]);
      if (transportRepaired) expect(activities.filter(a => a.kind === 'model_transport_retry')).toHaveLength(1);
      expect(cancelled).toBe(false);
      if (scenario !== 'measure') expect(activities.find(a => a.kind === 'document_program_sealed').detail).toMatchObject({ finishReason: 'stop', promptBytes: expect.any(Number), contentBytes: expect.any(Number), elapsedMs: expect.any(Number), deadlineSource: 'owned_turn', transportStreaming: true, transportCallCount: expect.any(Number), transportElapsedMs: expect.any(Number), transportFirstTokenMs: expect.any(Number), transportChunkCount: expect.any(Number), transportMaxIdleMs: expect.any(Number) });
      const retries = activities.filter(a => a.kind === 'document_program_retry');
      expect(retries).toHaveLength(Number(repaired));
      if (repaired) expect(retries[0].detail).toMatchObject({ sliceIndex: scenario === 'malformed-middle' ? 1 : 0, attempt: 1, attempts: 1, schemaHash: expect.stringMatching(/^[a-f0-9]{64}$/), commandDispatched: false });
      if (scenario === 'length-then-stop') expect(calls[2].messages.at(-1).content).toContain('Repair only this uncommitted continuation');
      if (scenario === 'oversize') expect(program?.slices).toHaveLength(1);
      if (scenario === 'whole-wire-large') {
        expect(program?.slices).toHaveLength(3);
        expect(program?.slices.map(slice => slice.code).join('')).toBe(fragments[0]);
        expect(program?.state).toBe('sealed');
        const wire = JSON.stringify({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({ code: fragments[0], final: true }) } }] });
        expect(Buffer.byteLength(wire)).toBeGreaterThan(50000);
      }
      if (scenario === 'sealed-large') expect(new TextEncoder().encode(proposals[0].proposal.command).length).toBeGreaterThan(12000);
      expect(events.filter(e => e.type === 'shell_proposal')).toHaveLength(1);
      if (scenario === 'measure') expect(program).toBeUndefined();
      else expect(timeline.indexOf('/propose')).toBeGreaterThan(timeline.lastIndexOf('/document-program/append'));
    } else {
      expect(proposals).toHaveLength(0); expect(cancelled).toBe(true); expect(calls).toHaveLength(scenario === 'transport-overflow' ? 1 : ['invalid-json', 'truncated', 'multiple-choices', 'tool-envelope', 'raw-html', 'ambiguous', 'timeout-exhausted', '520-exhausted'].includes(scenario) ? 4 : scenario === 'tampered-history' || scenario === 'stopped-retry' ? 3 : 2);
      if (scenario === 'refused' || scenario === 'content-filtered') {
        // Refusal is an explicit policy boundary, NOT malformed authoring and
        // never eligible for retry or a different provider.
        expect(events.filter(e => e.type === 'rejected')).toEqual([expect.objectContaining({ reason: scenario === 'refused' ? 'model_refusal' : 'provider_content_filter' })]);
        expect(activities.filter(a => a.kind === 'document_program_retry')).toEqual([]);
      } else if (scenario !== 'stopped' && scenario !== 'stopped-retry') {
        if (scenario === 'timeout-exhausted') expect(calls.map(c => c.max_tokens)).toEqual([1500, tokenLimit, tokenLimit, tokenLimit]);
        expect(events.filter(e => e.type === 'complete')).toEqual([expect.objectContaining({
          reply: scenario === 'transport-overflow'
            ? 'The complete source material exceeded the preparation limit. Nothing was shortened or silently left out. The confirmed steps are saved in Events.'
            : '',
          workIncomplete: true,
        })]);
        const terminal = events.filter(e => e.type === 'document_work_unavailable');
        expect(terminal).toHaveLength(1);
        if (scenario === 'timeout-exhausted') expect(terminal[0]).toMatchObject({ reason: 'document_authoring_timeout', check: 'provider_timeout', transportCallCount: 3, transportStreaming: true, tokenLimit });
        if (['invalid-json', 'truncated', 'multiple-choices', 'tool-envelope', 'raw-html', 'ambiguous', 'timeout-exhausted'].includes(scenario)) {
          expect(terminal[0]).toMatchObject({ check: expect.any(String), sliceIndex: 0, attempt: scenario === 'timeout-exhausted' ? 1 : 3, attempts: scenario === 'timeout-exhausted' ? 1 : 3, model: sonnet ? 'anthropic/claude-sonnet-4.6' : 'openai/gpt-4o', schemaHash: expect.stringMatching(/^[a-f0-9]{64}$/), stage: 'document_authoring', programID: program!.id, sliceCount: program!.slices.length, programSHA256: program!.prefixSHA256, tokenLimit: expect.any(Number), promptSections: expect.any(Object) });
          expect(events.find(e => e.type === 'tool_request_rejected')).toMatchObject({ check: terminal[0].check, sliceIndex: 0, attempt: scenario === 'timeout-exhausted' ? 1 : 3 });
        }
      }
    }
  });
});
