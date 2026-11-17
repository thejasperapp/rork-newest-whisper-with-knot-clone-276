// @vitest-environment node
// Runs the real live orchestrator against synthetic provider/actor boundaries.
// No native executor, model, droplet command, file capture or live service runs.
import { afterEach, describe, expect, it, vi } from 'vitest';
vi.mock('cloudflare:workers', () => ({ DurableObject: class {} }));
import { knotCreationTurnMs } from '../../functions/knot-turn-economics';
import { knotLive } from '../../functions/knot-live';
import { documentSkillReadCommand } from '../../functions/knot-document-proof';
import { resolvedKnotSelectionActivity, type KnotActivity } from '../../functions/knot-activity';

afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });
describe('captured-file completion presentation', () => {
  it.each(['visual_ai', 'issues', 'measured-memory'])('finishes with the captured card only, retaining %s evidence', async review => {
    const id = (n: number) => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');
    const document = { id: 'a'.repeat(64), proposalID: id(5), sourceMessageID: id(3), name: 'fixture.pdf', title: 'Reading Plan', format: 'pdf', size: 123, sha256: 'b'.repeat(64), review, qualityShortfalls: review === 'issues' ? ['Retained fixture finding'] : [], deliveryNote: 'Previously persisted note; never rewrite this record.' };
    const routes: string[] = [];
    const env = { SUPABASE_SERVICE_ROLE_KEY: 'synthetic-only', SIDECAR_TOKEN_WHISPER: 'synthetic-only', EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY: 'synthetic-only', EXPO_PUBLIC_TOOLKIT_URL: 'https://synthetic.invalid', DO: { fetch: vi.fn(async (request: Request) => {
      const path = new URL(request.url).pathname; routes.push(path);
      if (path === '/admit' || path === '/activity') return Response.json({ ok: true });
      if (path === '/persona/read') return Response.json({ version: 1, name: 'Knot', vibe: '' });
      if (path === '/discovery') return Response.json({ ok: true, service: 'knot-sidecar', tools: [] });
      if (path === '/receipt') return Response.json({ proposalID: id(5), bot: 'main', conversationID: id(4), status: 'completed', exitCode: 0, outputComplete: true, terminationConfirmed: true, stdout: '', stderr: '', reviewedCommand: 'fixture-only', evidence: [], ...(review === 'measured-memory' ? { workflow: { rootID: id(1), originalRequest: 'Create a PDF reading plan', mode: 'Create', documentTask: true, documentPipeline: 'agent_v2', documentPolicy: 'author_v1', memoryRead: true, indexRead: true, workspaceInspected: true, skills: [documentSkillReadCommand], commands: 8, memoryWritten: true, draftWritten: false, skillCreationCommand: 'cat /opt/knot-skills/skill-creation/SKILL.md' } } : {}), deliveredDocument: document });
      throw new Error('Unexpected actor route: ' + path);
    }) } };
    const provider = vi.fn(async () => { throw new Error('No post-capture narration model permitted'); }); vi.stubGlobal('fetch', provider);
    let pending: Promise<unknown> | undefined;
    const response = await knotLive(new Request('https://synthetic.invalid/knot/live', { method: 'POST', body: JSON.stringify({ requestID: id(1), consentVersion: 'knot_ai_consent_v4', message: 'Create a PDF reading plan', bot: 'main', healthContext: '', history: [], isWebQuery: false, sharedConversation: false, conversationID: id(4), sourceMessageID: id(3), shellResultID: id(5) }) }), env, id(2), { waitUntil: work => { pending = work; } });
    expect(response.status).toBe(200);
    const wire = await response.text(); await pending;
    const events = wire.split('\n\n').filter(frame => frame.startsWith('data: ')).map(frame => JSON.parse(frame.slice(6)));
    expect(events.filter(event => event.type === 'complete')).toEqual([expect.objectContaining({ reply: '' })]);
    expect(events.some(event => event.type === 'text')).toBe(false);
    expect(provider).not.toHaveBeenCalled();
    expect(routes.some(path => /capture|delivery-note|propose/.test(path))).toBe(false);
    expect(document.qualityShortfalls).toEqual(review === 'issues' ? ['Retained fixture finding'] : []);
    expect(document.deliveryNote).toBe('Previously persisted note; never rewrite this record.');
  });
});
describe('fresh write-failure terminal orchestration', () => {
  it('does not ask the model to reauthor after two owned failed writes', async () => {
    const id = (n: number) => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');
    const env = { SUPABASE_SERVICE_ROLE_KEY: 'synthetic-only', SIDECAR_TOKEN_WHISPER: 'synthetic-only', EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY: 'synthetic-only', EXPO_PUBLIC_TOOLKIT_URL: 'https://synthetic.invalid', DO: { fetch: vi.fn(async (request: Request) => {
      const path = new URL(request.url).pathname;
      if (path === '/admit' || path === '/activity') return Response.json({ ok: true });
      if (path === '/persona/read') return Response.json({ version: 1, name: 'Knot', vibe: '' });
      if (path === '/discovery') return Response.json({ ok: true, service: 'knot-sidecar', tools: [] });
      if (path === '/receipt') return Response.json({ proposalID: id(5), bot: 'main', conversationID: id(4), status: 'failed', exitCode: 73, outputComplete: true, terminationConfirmed: true, stdout: '', stderr: '', reviewedCommand: 'fixture-only', evidence: [], workflow: { rootID: id(1), originalRequest: 'Create a PDF reading plan', mode: 'Create', documentTask: true, documentDirectoryPolicy: 'output_parent_v1', documentWriteFailures: 2, documentPipeline: 'agent_v2', documentPolicy: 'author_v1', memoryRead: true, indexRead: true, workspaceInspected: true, skills: [documentSkillReadCommand], commands: 8, memoryWritten: false } });
      throw new Error('Unexpected actor route: ' + path);
    }) } };
    const provider = vi.fn(async () => { throw new Error('No reauthor model permitted'); }); vi.stubGlobal('fetch', provider);
    let pending: Promise<unknown> | undefined;
    const response = await knotLive(new Request('https://synthetic.invalid/knot/live', { method: 'POST', body: JSON.stringify({ requestID: id(1), consentVersion: 'knot_ai_consent_v4', message: 'Create a PDF reading plan', bot: 'main', healthContext: '', history: [], isWebQuery: false, sharedConversation: false, conversationID: id(4), sourceMessageID: id(3), shellResultID: id(5) }) }), env, id(2), { waitUntil: work => { pending = work; } });
    const wire = await response.text(); await pending;
    expect(wire).not.toContain('"type":"shell_review_ready"');
    const events = wire.split('\n\n').filter(frame => frame.startsWith('data: ')).map(frame => JSON.parse(frame.slice(6)));
    expect(events.filter(event => event.type === 'complete')).toEqual([expect.objectContaining({ reply: '', workIncomplete: true, reason: 'document_write_failures_no_replay' })]);
    expect(provider).not.toHaveBeenCalled();
  });
});
describe('live pre-dispatch selection repair orchestration', () => {
  it.each(['clause', 'resident', 'upstream-empty', 'truncated', 'stopped', 'exhausted', 'game-empty', 'game-written', 'game-no-work', 'provider-failure', 'game-provider-failure', 'claude', 'claude-empty', 'quality', 'v4-historical', 'timeout', 'timeout-exhausted', 'timeout-stop', 'truncated-timeout', 'game-timeout', 'http-unavailable', 'http-denied', 'progress', 'progress-unknown', 'timeout-floor'] as const)('retains exact evidence and owned boundaries: %s', async caseName => {
    const activity = { label: 'Draft the requested artifact', purpose: 'Prepare this request’s executable source for verification.' };
    const expanded = caseName.startsWith('claude');
    const scenario = ['claude', 'quality', 'v4-historical', 'progress', 'progress-unknown'].includes(caseName) ? 'clause' : caseName === 'claude-empty' ? 'upstream-empty' : caseName;
    const document = !scenario.startsWith('game');
    const requestID = '00000000-0000-4000-8000-000000000001';
    const taskID = '00000000-0000-4000-8000-000000000002';
    const sourceMessageID = '00000000-0000-4000-8000-000000000003';
    const conversationID = '00000000-0000-4000-8000-000000000004';
    const proposalID = '00000000-0000-4000-8000-000000000005';
    const aborter = new AbortController();
    const activities: KnotActivity[] = [], proposals: Record<string, unknown>[] = [], decisions: { max_tokens: number; messages: { role: string; content: string }[]; tool_choice?: string; stream?: boolean }[] = [];
    const unexpected: string[] = [];
    const capabilities = { ok: true, service: 'knot-sidecar', tools: [
      { name: 'session_input', method: 'POST', path: '/sessions/:id/input', request: { data: 'Exact command' } },
      { name: 'session_open', method: 'POST', path: '/sessions' },
      { name: 'session_status', method: 'GET', path: '/sessions/:id' },
      { name: 'session_read', method: 'GET', path: '/sessions/:id/log?offset=N' },
      { name: 'session_close', method: 'DELETE', path: '/sessions/:id' },
      { name: 'capabilities', method: 'GET', path: '/capabilities' },
    ] };
    const workflow = { ...(caseName === 'quality' ? { documentQuality: 'quality_v1' as const } : {}), rootID: taskID, sourceMessageID, originalRequest: document ? 'Create a PDF guide' : 'Build a playable creature-collecting game', mode: 'Create', documentTask: document, documentPipeline: 'agent_v2', documentPolicy: 'author_v1', memoryRead: true, indexRead: true, workspaceInspected: true, skills: document ? [documentSkillReadCommand] : [], commands: 4, memoryWritten: false };
    const env = { SUPABASE_SERVICE_ROLE_KEY: 'synthetic-signing-only', SIDECAR_TOKEN_WHISPER: 'synthetic-sidecar-only', EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY: 'synthetic-gateway-only', EXPO_PUBLIC_TOOLKIT_URL: 'https://synthetic.invalid', DO: { fetch: vi.fn(async (request: Request) => {
      const path = new URL(request.url).pathname;
      if (path === '/admit') return Response.json({ ok: true });
      if (path === '/persona/read') return Response.json({ version: 1, name: 'Knot', vibe: '' });
      const body = await request.json() as Record<string, unknown>;
      if (path === '/receipt') return Response.json({ proposalID, bot: 'main', conversationID, status: 'completed', exitCode: 0, sessionID: 'synthetic-owned-session', outputComplete: true, terminationConfirmed: true, truncated: false, stdout: '', stderr: '', reviewedCommand: 'cat -- synthetic-reference.md', workflow, evidence: scenario === 'game-written' ? [{ proposalID, operation: 'work', status: 'completed', exitCode: 0, outputComplete: true, terminationConfirmed: true, truncated: false }] : [], ...(caseName === 'quality' ? { documentChain: { version: 'knot_document_chain_v1', buildProposalID: proposalID, outputPath: 'synthetic.pdf', outputSHA256: 'a'.repeat(64), outputSize: 100, buildStatus: 'completed', sourceSHA256: 'b'.repeat(64), sourceSameBytes: true, remaining: ['independent_proof', 'content_comparison', 'visual_review', 'capture'], newBuildRequired: false } } : {}) });
      if (path === '/discovery') return Response.json(capabilities);
      if (path === '/workspace/resolve') return Response.json({ workspace: 'whisper-' + 'a'.repeat(48) });
      if (path === '/activity') {
        activities.push({ ...body, id: requestID + ':' + body.sequence, label: String(body.kind), recordedAt: '2026-11-12T06:00:00Z' } as KnotActivity);
        return Response.json({ ok: true });
      }
      if (path === '/propose') { proposals.push(body); return Response.json(body.proposal); }
      unexpected.push('actor:' + path); throw new Error('Unexpected synthetic actor route');
    }) } };
    vi.stubGlobal('fetch', vi.fn(async (url: string, init: RequestInit) => {
      expect(String(url)).toBe('https://synthetic.invalid/v2/vercel/v1/chat/completions');
      const body = JSON.parse(String(init.body)) as typeof decisions[number];
      decisions.push(body);
      expect((body as typeof body & { model: string }).model).toBe(expanded ? 'anthropic/claude-sonnet-4.6' : 'openai/gpt-4o');
      if (body.stream || body.max_tokens === 512) { unexpected.push('provider:answer-or-classification'); throw new Error('No answer substitution or reclassification allowed'); }
      const index = decisions.length;
      if (scenario.startsWith('http-')) return Response.json({ error: 'synthetic private provider body' }, { status: scenario === 'http-denied' ? 403 : 503 });
      if (scenario.endsWith('provider-failure')) throw new Error('provider_unavailable');
      if (scenario === 'timeout-stop') { aborter.abort(); throw new DOMException('Synthetic Stop', 'AbortError'); }
      if (scenario === 'timeout-floor' && index === 1) {
        const advancedNow = Date.now() + knotCreationTurnMs - 4000;
        vi.spyOn(Date, 'now').mockReturnValue(advancedNow);
        throw new DOMException('Synthetic selection deadline', 'TimeoutError');
      }
      if (scenario.includes('timeout') && (scenario === 'truncated-timeout' ? index === 2 : index === 1 || scenario === 'timeout-exhausted')) throw new DOMException('Synthetic selection deadline', 'TimeoutError');
      if (scenario === 'game-timeout') return Response.json({ choices: [{ finish_reason: 'tool_calls', message: { tool_calls: [{ id: 'synthetic_' + index, type: 'function', function: { name: 'session_input', arguments: JSON.stringify({ data: 'printf synthetic-only', _activity: activity }) } }] } }] });
      if (scenario === 'game-no-work') return Response.json({ choices: [{ finish_reason: 'tool_calls', message: { tool_calls: [{ id: 'synthetic_' + index, type: 'function', function: { name: 'capabilities', arguments: JSON.stringify({ _activity: activity }) } }] } }] });
      if (scenario === 'upstream-empty') return Response.json({ choices: [{ finish_reason: 'length', message: { content: '' } }], usage: { completion_tokens: 0 } });
      if (scenario === 'resident' && index === 1) return Response.json({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({ selection: { tool: 'document_script', arguments: { stage: 'source', interpreter: 'knot-doc', code: 'nonempty', path: 'synthetic.md', title: '', deliveryLabel: '', _activity: activity } } }) } }] });
      if (scenario === 'game-empty' || scenario === 'game-written') return Response.json({ choices: [{ finish_reason: 'stop', message: {} }] });
      if (scenario === 'stopped' && index === 2) { aborter.abort(); throw new DOMException('Synthetic Stop', 'AbortError'); }
      if (['truncated', 'truncated-timeout'].includes(scenario) && index === 1) return Response.json({ choices: [{ finish_reason: 'length', message: { content: '{"selection":{"arguments":' } }], usage: { completion_tokens: 6000 } });
      const invalid = scenario === 'exhausted' || scenario === 'clause' && index === 1 || scenario === 'stopped' && index === 1 || scenario === 'truncated' && index === 2;
      return Response.json({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({ selection: { tool: 'document_script', arguments: { stage: 'source', interpreter: 'python3', code: invalid ? '\u0000' : '# Synthetic source, never executed', path: 'knot-' + taskID + '-source.html', title: '', deliveryLabel: '', _activity: activity } } }) } }] });
    }));
    let pending: Promise<unknown> | undefined;
    const response = await knotLive(new Request('https://synthetic.invalid/knot/live', { method: 'POST', signal: aborter.signal, body: JSON.stringify({ requestID, consentVersion: ['quality', 'v4-historical'].includes(caseName) ? 'knot_ai_consent_v4' : 'knot_ai_consent_v3', ...(expanded ? { taskModelConsentVersion: 'knot_task_models_v1' } : {}), ...(caseName === 'progress' ? { workProgressVersion: 'knot_work_progress_v1' } : caseName === 'progress-unknown' ? { workProgressVersion: 'unknown' } : {}), ...(scenario === 'timeout-floor' ? { foregroundTurnVersion: 'knot_foreground_turn_v1' } : {}), message: workflow.originalRequest, bot: 'main', healthContext: '', history: [], isWebQuery: false, sharedConversation: false, conversationID, sourceMessageID, shellResultID: proposalID }) }), env, taskID, { waitUntil: work => { pending = work; } });
    expect(response.status).toBe(200);
    const wire = await response.text(); await pending;
    const events = wire.split('\n\n').filter(frame => frame.startsWith('data: ')).map(frame => JSON.parse(frame.slice(6)) as { type: string; sequence: number; phase?: string; reply?: string; workIncomplete?: boolean });
    expect(events.map(event => event.sequence)).toEqual(events.map((_, index) => index + 1));
    const progress = events.filter(event => event.type === 'work_phase');
    if (caseName === 'progress') {
      expect(progress).toHaveLength(1); // Not repeated on a retry or timer.
      expect(progress[0]).toMatchObject({ phase: 'preparing' });
      expect(Object.keys(progress[0]).sort()).toEqual(['phase', 'requestID', 'sequence', 'type', 'v']);
      expect(events.indexOf(progress[0])).toBeLessThan(events.findIndex(event => event.type === 'tool_selection_retry'));
    } else expect(progress).toHaveLength(0);
    const incomplete = events.filter(event => event.type === 'complete' && event.workIncomplete === true);
    for (const terminal of incomplete) expect(terminal.reply).toBe('');
    expect(events.some(event => event.type === 'text')).toBe(false);
    const conversationTerminals = events.filter(event => ['complete', 'error', 'rejected'].includes(event.type));
    expect(conversationTerminals).toHaveLength(['stopped', 'timeout-stop'].includes(scenario) ? 0 : 1);
    for (const terminal of events.filter(event => event.type === 'document_work_unavailable')) {
      const index = events.indexOf(terminal);
      expect(events[index + 1]).toMatchObject({ type: 'complete', reply: '', workIncomplete: true });
      expect(index + 1).toBe(events.length - 1);
    }
    expect(unexpected).toEqual([]);
    expect(activities.every(activity => activity.sourceMessageID === sourceMessageID && activity.requestID === requestID)).toBe(true);
    const bound = activities.findIndex(activity => activity.taskID === taskID);
    expect(bound).toBeGreaterThanOrEqual(0);
    expect(activities.slice(0, bound).every(activity => activity.taskID === requestID && activity.kind === 'accepted')).toBe(true);
    expect(activities.slice(bound).every(activity => activity.taskID === taskID)).toBe(true);
    const rejections = activities.filter(activity => ['tool_selection_retry', 'tool_selection_rejected'].includes(activity.kind));
    const outcomes = activities.filter(activity => activity.kind === 'tool_selection_outcome');
    const attempts = activities.filter(activity => activity.kind === 'tool_selection_attempt');
    const transportAttempts = activities.filter(activity => activity.kind === 'model_transport_attempt');
    const transportRetries = activities.filter(activity => activity.kind === 'model_transport_retry');
    const transportOutcomes = activities.filter(activity => activity.kind === 'model_transport_outcome');
    expect(transportAttempts).toHaveLength(decisions.length);
    expect(attempts).toHaveLength(decisions.length - transportRetries.length);
    const semanticDecisions = decisions.filter((decision, index) => {
      if (transportAttempts[index].detail?.transportAttempt === 1) return true;
      // A transport retry resends the exact model payload, not a repair prompt.
      expect(decision).toEqual(decisions[index - 1]);
      return false;
    });
    for (const [index, attempt] of attempts.entries()) {
      expect(attempt.detail).toMatchObject({ commandDispatched: false, tokenLimit: semanticDecisions[index].max_tokens });
      const sections = attempt.detail!.promptSections!;
      expect(sections.policyBytes! + sections.requestHistoryBytes! + sections.receiptBytes! + sections.assistantBytes! + sections.framingBytes!).toBe(attempt.detail!.promptBytes);
      expect(attempt.detail!.promptBytes).toBe(new TextEncoder().encode(JSON.stringify(semanticDecisions[index].messages)).length);
      expect(sections.contractBytes).toBeGreaterThan(0);
    }
    expect(JSON.stringify(activities)).not.toMatch(/Synthetic source|synthetic-gateway-only|synthetic-signing-only/);
    if (scenario === 'timeout-floor') {
      expect(decisions).toHaveLength(1);
      expect(proposals).toHaveLength(0);
      expect(incomplete).toHaveLength(1);
      expect(rejections).toHaveLength(0);
      expect(outcomes).toHaveLength(0);
      expect(transportRetries).toHaveLength(0);
      expect(transportOutcomes.map(event => event.detail?.transportOutcome)).toEqual(['ended']);
      expect(activities).toContainEqual(expect.objectContaining({ kind: 'tool_selection_unavailable', detail: expect.objectContaining({ reason: 'selection_timeout', commandDispatched: false }) }));
      return;
    }
    if (scenario === 'truncated-timeout') {
      expect(attempts.map(event => event.detail?.strategy)).toEqual(['initial', 'truncation_escalation']);
      expect(decisions.map(decision => decision.max_tokens)).toEqual([6000, 9000, 9000]);
      expect(proposals).toHaveLength(1);
      expect(outcomes[0].detail).toMatchObject({ attempts: 2, selectionRecovered: true, escalatedRetryRan: true, attemptedTokenLimit: 9000, outcome: 'recovered' });
      expect(rejections.map(event => event.detail?.reason)).toEqual(['selection_truncated']);
      expect(transportRetries).toHaveLength(1);
      expect(transportOutcomes.map(event => event.detail?.transportOutcome)).toEqual(['recovered']);
      return;
    }
    if (scenario.includes('timeout')) {
      // Immediate synthetic failures can use three transport attempts in each
      // of the two semantic menus; real stalls consume one shared clock below.
      expect(decisions).toHaveLength(scenario === 'timeout-stop' ? 1 : scenario === 'timeout-exhausted' ? 6 : 2);
      expect(attempts).toHaveLength(scenario === 'timeout-exhausted' ? 2 : 1);
      expect(rejections).toHaveLength(scenario === 'timeout-exhausted' ? 1 : 0);
      expect(outcomes).toHaveLength(0);
      expect(proposals).toHaveLength(['timeout', 'game-timeout'].includes(scenario) ? 1 : 0);
      if (scenario === 'timeout-stop') {
        expect(rejections).toHaveLength(0);
        expect(activities.some(activity => activity.kind === 'cancelled')).toBe(true);
      } else {
        expect(attempts[0].detail).toMatchObject({ attempt: 1, stage: 'tool_selection', selectionPhase: document ? 'document_authoring' : 'artifact_authoring', deadlineMs: expect.any(Number), promptBytes: expect.any(Number), commandDispatched: false });
        expect(attempts[0].detail!.promptBytes).toBeGreaterThan(0);
        // Legacy 55s handoff: each transport call remains clipped to ownership.
        expect(attempts[0].detail!.deadlineMs).toBeGreaterThan(25000);
        expect(attempts[0].detail!.deadlineMs).toBeLessThanOrEqual(50000);
        expect(transportRetries).toHaveLength(scenario === 'timeout-exhausted' ? 4 : 1);
        expect(transportOutcomes.map(event => event.detail?.transportOutcome)).toEqual(scenario === 'timeout-exhausted' ? ['ended', 'ended'] : ['recovered']);
        if (scenario === 'timeout-exhausted') expect(attempts.map(event => event.detail?.strategy)).toEqual(['initial', 'minimal_menu_retry']);
        if (scenario === 'timeout-exhausted') expect(incomplete).toHaveLength(1);
      }
      expect(JSON.stringify(activities)).not.toContain('printf synthetic-only');
      return;
    }
    if (scenario.startsWith('http-')) {
      expect(decisions).toHaveLength(scenario === 'http-denied' ? 1 : 6); expect(proposals).toHaveLength(0);
      expect(transportRetries).toHaveLength(scenario === 'http-denied' ? 0 : 4);
      expect(transportOutcomes.map(event => event.detail?.transportOutcome)).toEqual(scenario === 'http-denied' ? [] : ['ended', 'ended']);
      expect(rejections).toHaveLength(scenario === 'http-denied' ? 0 : 1);
      // Policy/account HTTP rejections retain the existing explicit boundary,
      // rather than being relabelled as ordinary quiet work incompleteness.
      if (scenario === 'http-denied') expect(events.some(event => event.type === 'rejected')).toBe(true);
      else expect(incomplete).toHaveLength(1);
      expect(activities).toContainEqual(expect.objectContaining({ kind: 'tool_selection_unavailable', detail: expect.objectContaining({ reason: 'upstream_http_rejection', status: scenario === 'http-denied' ? 403 : 503, elapsedMs: expect.any(Number), deadlineMs: expect.any(Number), promptBytes: expect.any(Number), commandDispatched: false }) }));
      expect(JSON.stringify(activities)).not.toContain('synthetic private provider body');
      return;
    }
    if (scenario.endsWith('provider-failure')) {
      expect(activities).toContainEqual(expect.objectContaining({ kind: 'tool_selection_unavailable', detail: expect.objectContaining({ reason: 'tool_unavailable', elapsedMs: expect.any(Number), deadlineMs: expect.any(Number), promptBytes: expect.any(Number), commandDispatched: false }) }));
      expect(decisions).toHaveLength(1);
      expect(proposals).toHaveLength(0);
      expect(incomplete).toHaveLength(1);
      expect(activities).toContainEqual(expect.objectContaining({ kind: 'error', detail: expect.objectContaining({ stage: 'tool_selection', reason: 'provider_unavailable' }) }));
      return;
    }
    if (scenario === 'game-no-work') {
      expect(decisions).toHaveLength(4);
      expect(proposals).toHaveLength(0);
      // Valid capability observations are not creation work. Exhausting that
      // menu must still close without a proposal or an invented deliverable.
      expect(activities).toContainEqual(expect.objectContaining({ kind: 'document_work_unavailable', detail: expect.objectContaining({ reason: 'document_next_step_not_prepared', commands: 4 }) }));
      expect(incomplete).toHaveLength(1);
      return;
    }
    if (scenario === 'upstream-empty') {
      expect(decisions).toHaveLength(2);
      expect(attempts.map(event => event.detail?.strategy)).toEqual(['initial', 'minimal_menu_retry']);
      expect(decisions[0].max_tokens).toBe(6000);
      expect(proposals).toHaveLength(0);
      expect(activities).toContainEqual(expect.objectContaining({ kind: 'tool_selection_rejected', detail: expect.objectContaining({ reason: 'selection_upstream_empty' }) }));
      expect(incomplete).toHaveLength(1);
      return;
    }
    expect(outcomes).toHaveLength(1);
    expect(rejections.length).toBeGreaterThan(0);
    expect(outcomes[0].detail?.selectionIncident).toBe(rejections[0].detail?.selectionIncident);
    expect(outcomes[0].detail?.attempts).toBe(decisions.length);
    expect(outcomes[0].detail?.repairAttempts).toBe(decisions.length - 1);
    expect(rejections[0].detail).toMatchObject({ attempt: 1, tokenLimit: 6000, outcome: 'pending' });
    if (document) {
      const clauseAttempt = scenario === 'truncated' ? 1 : 0;
      expect(rejections[clauseAttempt].detail?.fields).toEqual(scenario === 'resident' ? ['arguments.interpreter:enum'] : ['arguments.code:control']);
      expect(decisions[clauseAttempt + 1].messages.some(message => message.role === 'system' && message.content.includes(scenario === 'resident' ? '["arguments.interpreter:enum"]' : '["arguments.code:control"]'))).toBe(true);
    } else {
      expect(decisions.every(decision => decision.tool_choice === 'required')).toBe(true);
      expect(rejections[0].detail?.reason).toBe('requested_work_step_required');
    }
    if (scenario === 'clause' || scenario === 'resident' || scenario === 'truncated') {
      expect(proposals).toHaveLength(1);
      const systemMessages = decisions[0].messages.filter(message => message.role === 'system').map(message => message.content);
      const finalPolicy = systemMessages.findIndex(message => message.startsWith('FINAL FRESH DOCUMENT QUALITY POLICY'));
      if (caseName === 'quality') {
        expect(finalPolicy).toBeGreaterThan(systemMessages.findIndex(message => message.includes('BUILD SIDE-EFFECT LATCH')));
        // The owner's standing November 14 policy makes visual judgment
        // advisory, not missing proof bytes or a fictional quality pass.
        expect(systemMessages[finalPolicy]).toContain('failed mechanical proof NEVER qualify');
        expect(systemMessages[finalPolicy]).toContain('Visual judgment, reviewer outage or uncertain visual verdict is advisory');
        expect(systemMessages[finalPolicy]).toContain('mechanically validate every required PNG independently');
        expect(systemMessages[finalPolicy]).toContain('record any unavailable judgment without a pass');
        expect(systemMessages[finalPolicy]).toContain('No separate image-review switch');
        const descriptor = JSON.parse(decisions[0].messages.find(message => message.content.startsWith('OWNED ROUTING DESCRIPTOR'))!.content.split('\n').slice(1).join('\n'));
        expect(descriptor.continuation).toMatchObject({ newBuildRequired: false, buildProposalID: proposalID, remaining: ['independent_proof', 'content_comparison', 'visual_review', 'capture'] });
        expect((proposals[0].workflow as { documentQuality?: string }).documentQuality).toBe('quality_v1');
      } else {
        expect(finalPolicy).toBe(-1);
        expect((proposals[0].workflow as { documentQuality?: string }).documentQuality).toBeUndefined();
      }
      expect(proposals[0]).toMatchObject({ proposal: { tool: 'document_script', documentInvocation: { stage: 'source', code: '# Synthetic source, never executed' } }, workflow: { rootID: taskID, parentID: proposalID } });
      expect(outcomes[0].detail).toMatchObject({ outcome: 'recovered', selectionRecovered: true });
      const resolved = resolvedKnotSelectionActivity(activities).find(activity => activity.id === rejections[0].id);
      expect(resolved?.detail).toMatchObject({ outcome: 'recovered', tokenLimit: 6000, attempts: decisions.length });
      expect(wire).toContain('shellProposal');
    } else {
      expect(proposals).toHaveLength(0);
      expect(outcomes[0].detail).toMatchObject({ outcome: scenario === 'stopped' ? 'ended' : 'degraded', selectionRecovered: false });
      if (scenario === 'stopped') expect(activities.some(activity => activity.kind === 'cancelled')).toBe(true);
      else expect(incomplete).toHaveLength(1);
    }
    if (scenario === 'truncated') {
      expect(decisions.map(decision => decision.max_tokens)).toEqual([6000, 9000, 9000]);
      expect(rejections[0].detail).toMatchObject({ reason: 'selection_truncated', argumentBytes: 0, contentBytes: 26, contentShape: 'partial_json', completionTokens: 6000 });
    }
    expect(JSON.stringify(activities)).not.toContain('Synthetic source');
    expect(JSON.stringify(activities)).not.toContain('synthetic-gateway-only');
    expect(wire).not.toContain('tool_selection_outcome');
  });
});
