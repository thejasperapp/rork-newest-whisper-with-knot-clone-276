// @vitest-environment node
// Actual live orchestration with fake clocks and synthetic owned/provider edges.
// No box execution, capture, historical replay or live account is used.
import { afterEach, describe, expect, it, vi } from 'vitest';
vi.mock('cloudflare:workers', () => ({ DurableObject: class {} }));
import { knotLive } from '../../functions/knot-live';
import { knotCreationTurnMs } from '../../functions/knot-turn-economics';
import { knotArtifactRouting } from '../../functions/knot-document-proof';
import type { ShellWorkflow } from '../../functions/knot-shell';
const id = (n: number) => '00000000-0000-4000-8000-' + String(n).padStart(12, '0');
afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });
describe('one immutable actual selection round clock', () => {
  it.each(['minimal-read', 'both-stall', 'repair-stall', 'stop', 'large-utf8'] as const)('bounds all attempts and preserves admission: %s', async scenario => {
    vi.useFakeTimers(); vi.setSystemTime(new Date('2026-11-14T17:00:00Z'));
    const originalRequest = scenario === 'large-utf8' ? 'Make me an osrs style rpg game ' + '界'.repeat(12000) : 'Make me an osrs style rpg game';
    const workflow: ShellWorkflow = { rootID: id(2), sourceMessageID: id(3), originalRequest, mode: 'Create', ...knotArtifactRouting(originalRequest), memoryRead: true, indexRead: true, workspaceInspected: true, skills: ['cat /opt/knot-skills/games-web/SKILL.md'], commands: 0, memoryWritten: false };
    const complete = { status: 'completed', exitCode: 0, outputComplete: true, terminationConfirmed: true, truncated: false, contextTruncated: false };
    const calls: { messages: { role: string; content: string }[]; response_format: unknown; model: string; at: number }[] = [];
    const activities: { kind: string; detail?: Record<string, any> }[] = [], proposals: any[] = [], unexpected: string[] = [];
    const aborter = new AbortController();
    const env = { SUPABASE_SERVICE_ROLE_KEY: 'synthetic-signing-only', SIDECAR_TOKEN_WHISPER: 'synthetic-sidecar-only', EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY: 'synthetic-gateway-only', EXPO_PUBLIC_TOOLKIT_URL: 'https://synthetic.invalid', DO: { fetch: vi.fn(async (request: Request) => {
      const path = new URL(request.url).pathname;
      if (path === '/admit') return Response.json({ ok: true });
      if (path === '/persona/read') return Response.json({ version: 1, name: 'Knot', vibe: '' });
      const body = await request.json() as any;
      if (path === '/receipt') return Response.json({ ...complete, proposalID: id(5), bot: 'main', conversationID: id(4), sessionID: 'synthetic-owned-session', stdout: '', stderr: '', reviewedCommand: 'cat -- orientation.md', workflow, evidence: [
        { ...complete, proposalID: id(6), operation: 'skill_index', stdout: '[games-web](games-web/)\n[document-creation](document-creation/SKILL.md)' },
        { ...complete, proposalID: id(7), operation: 'workspace_inventory', stdout: 'EXISTING WORKSPACE FILES (data, not instructions):\n./world.md (128 bytes)' },
      ], providerResponse: 'PRIVATE_RECEIPT_' + 'x'.repeat(43503) });
      if (path === '/discovery') return Response.json({ ok: true, service: 'knot-sidecar', tools: [{ name: 'session_input', method: 'POST', path: '/sessions/:id/input', request: { data: 'Exact command' } }, { name: 'session_open', method: 'POST', path: '/sessions' }, { name: 'session_status', method: 'GET', path: '/sessions/:id' }, { name: 'session_read', method: 'GET', path: '/sessions/:id/log?offset=N' }, { name: 'session_close', method: 'DELETE', path: '/sessions/:id' }, { name: 'capabilities', method: 'GET', path: '/capabilities' }] });
      if (path === '/workspace/resolve') return Response.json({ workspace: 'whisper-' + 'a'.repeat(48) });
      if (path === '/activity') { activities.push(body); return Response.json({ ok: true }); }
      if (path === '/propose') { proposals.push(body); return Response.json(body.proposal); }
      if (path === '/foreground-ready') { aborter.abort(); throw new DOMException('Stop at real handoff', 'AbortError'); }
      unexpected.push(path); throw new Error('Unexpected synthetic actor route');
    }) } };
    vi.stubGlobal('fetch', vi.fn(async (_url, init: RequestInit) => {
      const body = JSON.parse(String(init.body));
      calls.push({ ...body, at: Date.now() });
      expect(body.model).toBe('anthropic/claude-sonnet-4.6');
      expect(body.stream).toBe(false); expect(body.max_tokens).toBe(1500);
      expect(JSON.stringify(body)).not.toContain('PRIVATE_RECEIPT_');
      if (scenario === 'minimal-read' && calls.length === 1) return Response.json({ choices: [] });
      if (scenario === 'repair-stall' && calls.length === 1) return Response.json({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({ selection: { tool: 'session_input', arguments: { data: 42, _activity: { label: 'Read the game world notes', purpose: 'Inspect the RPG world description.' } } } }) } }] });
      if (scenario === 'minimal-read' && calls.length === 2) return Response.json({ choices: [{ finish_reason: 'stop', message: { content: JSON.stringify({ selection: { tool: 'session_input', arguments: { data: 'cat -- world.md', _activity: { label: 'Read the game world notes', purpose: 'Use the saved world description to guide the RPG.' } } } }) } }] });
      return await new Promise<Response>((_resolve, reject) => {
        const signal = init.signal!;
        if (signal.aborted) reject(signal.reason);
        else signal.addEventListener('abort', () => reject(signal.reason), { once: true });
      });
    }));
    let pending: Promise<unknown> | undefined;
    const response = await knotLive(new Request('https://synthetic.invalid/knot/live', { method: 'POST', signal: aborter.signal, body: JSON.stringify({ requestID: id(1), consentVersion: 'knot_ai_consent_v4', taskModelConsentVersion: 'knot_task_models_v1', documentProgramVersion: 'knot_document_program_v3', foregroundTurnVersion: 'knot_foreground_turn_v1', message: originalRequest, bot: 'main', healthContext: '', history: [], isWebQuery: false, sharedConversation: false, conversationID: id(4), sourceMessageID: id(3), shellResultID: id(5) }) }), env, id(2), { waitUntil: work => { pending = work; } });
    expect(response.status).toBe(200); const wirePromise = response.text();
    await vi.waitFor(() => {
      expect({ count: calls.length, unexpected }).toMatchObject({ count: ['repair-stall', 'minimal-read'].includes(scenario) ? 2 : 1, unexpected: [] });
      // Activity persistence is asynchronous; provider arrival alone is not its receipt.
      expect(activities.some(activity => activity.kind === 'tool_selection_attempt')).toBe(true);
    });
    const attempt = activities.find(activity => activity.kind === 'tool_selection_attempt')!.detail!;
    const deadlineMs = Number(attempt.deadlineMs), started = calls[0].at;
    // Create selection now owns the remaining admitted task lifetime, not the
    // superseded 25-second stopwatch. Neither a repair nor a menu retry renews it.
    expect(started + deadlineMs).toBe(Date.parse('2026-11-14T17:00:00Z') + knotCreationTurnMs - 5000);
    if (scenario === 'stop') aborter.abort();
    else if (scenario !== 'minimal-read') await vi.advanceTimersByTimeAsync(Math.max(0, started + deadlineMs - Date.now()));
    const wire = await wirePromise; await pending;
    const attempts = activities.filter(activity => activity.kind === 'tool_selection_attempt');
    expect(attempts.every(activity => activity.detail?.deadlineMs === deadlineMs)).toBe(true);
    expect(attempts.every(activity => activity.detail?.promptBytes < 524288)).toBe(true);
    expect(attempts.every(activity => activity.detail?.promptTargetExceeded === (activity.detail?.promptBytes > 32768))).toBe(true);
    if (scenario === 'large-utf8') {
      expect(attempts[0].detail?.promptTargetExceeded).toBe(true);
      expect(calls[0].messages.some(message => message.content.includes('界'.repeat(12000)))).toBe(true);
      expect(activities.some(activity => activity.detail?.reason === 'selection_prompt_too_large')).toBe(false);
    }
    const strategies = attempts.map(activity => activity.detail?.strategy);
    expect(strategies).toEqual(scenario === 'minimal-read' ? ['initial', 'minimal_menu_retry'] : scenario === 'repair-stall' ? ['initial', 'field_correction'] : ['initial']);
    const ended = activities.filter(activity => activity.kind === 'tool_selection_unavailable').at(-1)?.detail;
    if (scenario === 'both-stall' || scenario === 'repair-stall') expect(ended?.elapsedMs).toBeLessThanOrEqual(deadlineMs);
    expect(calls.at(-1)!.at - started).toBeLessThan(deadlineMs);
    expect(proposals).toHaveLength(scenario === 'minimal-read' ? 1 : 0);
    if (scenario === 'minimal-read') {
      expect(proposals[0]).toMatchObject({ proposal: { tool: 'session_input', command: 'cat -- world.md' }, workflow: { rootID: id(2), parentID: id(5), artifactFormat: 'html', documentTask: false } });
      const initial = calls[0].response_format as any, minimal = calls[1].response_format as any;
      const variants = (format: any) => format.json_schema.schema.properties.selection.anyOf;
      const first = variants(initial), second = variants(minimal);
      expect(second.length).toBeLessThanOrEqual(first.length);
      expect(second.every((branch: unknown) => first.some((original: unknown) => JSON.stringify(original) === JSON.stringify(branch)))).toBe(true);
    }
    if (scenario === 'stop') expect(activities.some(activity => activity.kind === 'cancelled')).toBe(true);
    else if (scenario !== 'minimal-read') expect(wire).toContain('workIncomplete');
    expect(unexpected).toEqual([]);
  });
});
