// @vitest-environment node
// Actual orchestrator, synthetic actor/provider only. No remote execution or replay.
import { afterEach, describe, expect, it, vi } from 'vitest';
import { createHash } from 'node:crypto';
vi.mock('cloudflare:workers', () => ({ DurableObject: class {} }));
import { knotCreationTurnMs } from '../../functions/knot-turn-economics';
import { knotLive } from '../../functions/knot-live';
import { documentSkillReadCommand } from '../../functions/knot-document-proof';
import type { KnotActivity } from '../../functions/knot-activity';

afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });
describe('document argument terminal evidence at zero work', () => {
  it.each(['corrected', 'identical', 'foreground-identical', 'deadline', 'foreground-deadline', 'maximum', 'different-tools', 'last-command', 'no-budget', 'size-characters', 'size-unicode', 'size-escaping', 'size-response', 'size-valid', 'size-legacy', 'size-unknown', 'size-actor'] as const)('%s preserves repair, diagnostics and quiet closure', async scenario => {
    const requestID = '00000000-0000-4000-8000-000000000001';
    const taskID = '00000000-0000-4000-8000-000000000002';
    const sourceMessageID = '00000000-0000-4000-8000-000000000003';
    const conversationID = '00000000-0000-4000-8000-000000000004';
    const proposalID = '00000000-0000-4000-8000-000000000005';
    const foreground = scenario.startsWith('foreground-');
    const commands = scenario === 'no-budget' ? 10000 : scenario === 'last-command' ? 9999 : 0;
    const workflow = { rootID: taskID, sourceMessageID, originalRequest: 'Create a PDF guide', mode: 'Create', documentTask: true, documentPipeline: 'agent_v2', documentPolicy: 'author_v1', memoryRead: true, indexRead: true, workspaceInspected: true, skills: [documentSkillReadCommand], commands, memoryWritten: false };
    const activities: KnotActivity[] = [], proposals: Record<string, unknown>[] = [];
    const decisions: { response_format: unknown; messages: { role: string; content: string }[] }[] = [];
    const order: string[] = [];
    const start = Date.now();
    const clock = vi.spyOn(Date, 'now').mockReturnValue(start);
    const env = { SUPABASE_SERVICE_ROLE_KEY: 'synthetic-only', SIDECAR_TOKEN_WHISPER: 'synthetic-only', EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY: 'synthetic-only', EXPO_PUBLIC_TOOLKIT_URL: 'https://synthetic.invalid', DO: { fetch: vi.fn(async (request: Request) => {
      const path = new URL(request.url).pathname;
      if (path === '/admit') return Response.json({ ok: true });
      const body = await request.json() as Record<string, unknown>;
      if (path === '/receipt') return Response.json({ proposalID, bot: 'main', conversationID, status: 'completed', exitCode: 0, sessionID: 'synthetic-owned', outputComplete: true, terminationConfirmed: true, truncated: false, stdout: '', stderr: '', reviewedCommand: 'cat -- synthetic-reference.md', workflow, evidence: [] });
      if (path === '/discovery') return Response.json({ ok: true, service: 'knot-sidecar', tools: [
        { name: 'session_input', method: 'POST', path: '/sessions/:id/input', request: { data: 'Exact command' } },
        { name: 'session_open', method: 'POST', path: '/sessions' },
        { name: 'session_status', method: 'GET', path: '/sessions/:id' },
        { name: 'session_read', method: 'GET', path: '/sessions/:id/log?offset=N' },
        { name: 'session_close', method: 'DELETE', path: '/sessions/:id' },
      ] });
      if (path === '/workspace/resolve') return Response.json({ workspace: 'whisper-' + 'a'.repeat(48) });
      if (path === '/activity') { activities.push(body as KnotActivity); order.push(String(body.kind)); return Response.json({ ok: true }); }
      if (path === '/propose') { proposals.push(body); order.push('propose'); return scenario === 'size-actor' ? Response.json({ error: 'invalid_document_invocation', fields: ['arguments:size'], sizeFacts: { argumentBytes: 74001, argumentByteLimit: 74000, privateSource: 'never retained' } }, { status: 400 }) : Response.json(body.proposal); }
      throw new Error('Unexpected synthetic actor route: ' + path);
    }) } };
    vi.stubGlobal('fetch', vi.fn(async (url: string, init: RequestInit) => {
      expect(String(url)).toBe('https://synthetic.invalid/v2/vercel/v1/chat/completions');
      const body = JSON.parse(String(init.body));
      expect(body.stream).toBe(false);
      expect(body.model).toBe('openai/gpt-4o');
      expect(body.response_format).toBeDefined();
      decisions.push(body); order.push('decision:' + decisions.length);
      const attempt = decisions.length;
      if (scenario.includes('deadline')) clock.mockReturnValue(start + (foreground ? knotCreationTurnMs - 14000 : 41000));
      if (scenario === 'size-response') return new Response('x'.repeat(200001));
      const corrected = scenario.startsWith('size-') || ['corrected', 'last-command'].includes(scenario) && attempt === 2 || scenario === 'different-tools' && attempt === 4;
      const code = scenario === 'size-characters' ? '#'.repeat(64001) : scenario === 'size-unicode' ? '🪢'.repeat(19000) : scenario === 'size-escaping' ? '\u0001'.repeat(12500) : scenario.startsWith('size-') ? '# private synthetic source, never executed\n' + '#'.repeat(20000) : '# private synthetic source, never executed';
      const args = { stage: 'source', interpreter: 'python3', code, path: 'knot-' + taskID + '-source.html', title: '', deliveryLabel: '', _activity: { label: 'Draft the PDF guide', purpose: 'Write the guide’s source before building its PDF.' } };
      const invalid = scenario === 'different-tools' ? null : { ...args, ...(scenario === 'maximum' && attempt % 2 === 0 ? { deliveryLabel: undefined } : { title: undefined }) };
      return Response.json({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({ selection: { tool: !corrected && scenario === 'different-tools' && attempt % 2 === 0 ? 'session_input' : 'document_script', arguments: corrected ? args : invalid } }) } }] });
    }));
    let pending: Promise<unknown> | undefined;
    const response = await knotLive(new Request('https://synthetic.invalid/knot/live', { method: 'POST', body: JSON.stringify({ requestID, consentVersion: 'knot_ai_consent_v3', message: workflow.originalRequest, bot: 'main', healthContext: '', history: [], isWebQuery: false, sharedConversation: false, conversationID, sourceMessageID, shellResultID: proposalID, ...(foreground ? { foregroundTurnVersion: 'knot_foreground_turn_v1' } : {}), ...(scenario.startsWith('size-') && scenario !== 'size-legacy' ? { documentProgramVersion: scenario === 'size-unknown' ? 'unknown' : 'knot_document_program_v2' } : {}) }) }), env, taskID, { waitUntil: work => { pending = work; } });
    const wire = await response.text(); await pending;
    const events = wire.split('\n\n').filter(frame => frame.startsWith('data: ')).map(frame => JSON.parse(frame.slice(6)));
    const repairs = activities.filter(item => item.kind === 'tool_selection_retry');
    const terminal = activities.filter(item => item.kind === 'document_work_unavailable');
    const completions = events.filter(event => ['complete', 'error', 'rejected'].includes(event.type));
    expect(completions).toHaveLength(1);
    expect(events.some(event => event.type === 'text')).toBe(false);
    expect(JSON.stringify(activities)).not.toContain('private synthetic');
    expect(JSON.stringify(activities)).not.toContain('synthetic-only');
    if (scenario.startsWith('size-')) {
      expect(decisions).toHaveLength(1);
      expect(repairs).toHaveLength(0);
      expect(JSON.stringify(activities)).not.toContain('never retained');
      if (scenario === 'size-valid') {
        expect(proposals).toHaveLength(1); expect(terminal).toHaveLength(0);
        const proposal = proposals[0].proposal as { command: string; documentInvocation: { code: string } };
        expect(proposal.documentInvocation.code.length).toBeGreaterThan(8000);
        expect(proposal.command).toContain(JSON.stringify(JSON.stringify(proposal.documentInvocation)));
        const delivered = JSON.parse(completions[0].reply.split('\n')[1]);
        expect(delivered.shellProposal.documentInvocation.code).toBe(proposal.documentInvocation.code);
      } else {
        expect(proposals).toHaveLength(scenario === 'size-actor' ? 1 : 0);
        expect(terminal).toHaveLength(1);
        expect(completions[0]).toMatchObject({ type: 'complete', reply: '', workIncomplete: true });
        expect(terminal[0].detail).toMatchObject({ commandDispatched: false, terminationExit: ['size-legacy', 'size-unknown'].includes(scenario) ? 'client_capacity_exceeded' : 'size_capacity_exceeded' });
        if (['size-characters', 'size-unicode', 'size-escaping'].includes(scenario)) {
          const code = scenario === 'size-characters' ? '#'.repeat(64001) : scenario === 'size-unicode' ? '🪢'.repeat(19000) : '\u0001'.repeat(12500);
          const args = { stage: 'source', interpreter: 'python3', code, path: 'knot-' + taskID + '-source.html', title: '', deliveryLabel: '', _activity: { label: 'Draft the PDF guide', purpose: 'Write the guide’s source before building its PDF.' } };
          expect(terminal[0].detail?.sizeFacts).toEqual({ codeCharacters: Array.from(code).length, codeCharacterLimit: 64000, codeBytes: new TextEncoder().encode(code).length, argumentBytes: new TextEncoder().encode(JSON.stringify(args)).length, argumentByteLimit: 74000 });
        } else if (scenario === 'size-actor') expect(terminal[0].detail?.sizeFacts).toEqual({ argumentBytes: 74001, argumentByteLimit: 74000 });
        else if (scenario !== 'size-response') expect(terminal[0].detail?.sizeFacts).toMatchObject({ commandByteLimit: 12000, commandBytes: expect.any(Number) });
      }
      return;
    }
    if (['corrected', 'different-tools', 'last-command'].includes(scenario)) {
      const attempts = scenario === 'different-tools' ? 4 : 2;
      expect(decisions).toHaveLength(attempts);
      expect(proposals).toHaveLength(1);
      expect(repairs).toHaveLength(attempts - 1);
      expect(order.indexOf('propose')).toBeGreaterThan(order.indexOf('decision:' + attempts));
      expect(terminal).toHaveLength(0);
      expect(completions[0].workIncomplete).not.toBe(true);
      expect(activities.find(item => item.kind === 'tool_selection_outcome')?.detail).toMatchObject({ attempts, repairAttempts: attempts - 1, selectionRecovered: true, outcome: 'recovered' });
      return;
    }
    expect(proposals).toHaveLength(0);
    expect(terminal).toHaveLength(1);
    expect(completions[0]).toMatchObject({ type: 'complete', reply: '', workIncomplete: true });
    expect(events.indexOf(completions[0])).toBe(events.length - 1);
    expect(events.findIndex(event => event.type === 'document_work_unavailable')).toBeLessThan(events.indexOf(completions[0]));
    if (scenario === 'no-budget') {
      expect(decisions).toHaveLength(0);
      expect(terminal[0].detail).toMatchObject({ commands: 10000, reason: 'workflow_command_limit_reached', terminationExit: 'budget_exhausted' });
      return;
    }
    // The established minimal-menu recovery adds one pre-dispatch attempt
    // inside the same deadline after the original repair policy is exhausted.
    const attempts = scenario.includes('identical') ? 4 : scenario === 'maximum' ? 14 : 2;
    const terminationExit = 'repair_attempts_exhausted';
    expect(decisions).toHaveLength(attempts);
    expect(repairs).toHaveLength(attempts - 1);
    expect(terminal[0].detail).toMatchObject({ reason: 'invalid_tool_arguments', commands: 0, commandLimit: 10000, tool: 'document_script', fields: [scenario === 'maximum' ? 'arguments.deliveryLabel:required' : 'arguments.title:required'], attempts, repairAttempts: attempts - 1, terminationExit, outcome: 'degraded', commandDispatched: false, schemaHash: createHash('sha256').update(JSON.stringify(decisions.at(-1)!.response_format)).digest('hex') });
    expect(activities.find(item => item.kind === 'tool_selection_rejected')?.detail).toMatchObject({ terminationExit, schemaHash: terminal[0].detail?.schemaHash });
    for (let index = 1; index < decisions.length; index++) expect(decisions[index].messages.some(message => message.role === 'system' && message.content.startsWith(index === decisions.length - 1 ? 'MINIMAL ELIGIBLE MENU RETRY' : 'Trusted field corrections'))).toBe(true);
  });
});
